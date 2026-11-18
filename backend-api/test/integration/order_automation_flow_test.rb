require "test_helper"

# End-to-end checks of the order automation MVP through the real HTTP API:
# checkout -> order persisted -> confirmation queued/sent -> admin status change ->
# status notification -> customer timeline, plus retry, idempotency and stock restoration.
class OrderAutomationFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  ADDRESS = {
    full_name: "Casey Customer", email: "casey@example.com", phone: "9876543211",
    address: "12 MG Road", city: "Chennai", state: "Tamil Nadu", zip_code: "600001",
  }.freeze

  setup do
    ActionMailer::Base.deliveries.clear
    @customer = users(:one)
    @admin = users(:admin)
    @variant = product_variants(:one)
    @product = products(:one)
  end

  test "customer checkout is saved under the customer and queues a confirmation email after commit" do
    token = login(@customer)

    assert_enqueued_with(job: NotificationDeliveryJob) do
      place_order(token, quantity: 2)
    end
    assert_response :created

    order = Order.last
    assert_equal @customer, order.user, "order must belong to the logged-in customer, not the guest account"
    assert_equal "casey@example.com", order.customer_email
    assert_equal "Casey Customer", order.customer_name
    assert_equal [ nil, "pending" ], [ order.status_events.first.from_status, order.status_events.first.to_status ]

    # Server-side totals: client-sent tax/shipping (1 / -500) are ignored.
    assert_equal 1200.to_d, order.subtotal
    assert_equal 0.to_d, order.shipping_fee # free shipping above 999
    assert_equal 216.to_d, order.tax
    assert_equal 1416.to_d, order.total
    assert_equal 8, @variant.reload.stock

    delivery = order.notification_deliveries.sole
    assert_equal [ "order_confirmation", "pending" ], [ delivery.kind, delivery.status ]

    perform_enqueued_jobs
    assert_equal "sent", delivery.reload.status
    assert_equal 1, delivery.attempts
    mail = ActionMailer::Base.deliveries.sole
    assert_equal [ "casey@example.com" ], mail.to
    assert_includes mail.subject, order.order_number
    html = mail.html_part.body.decoded
    [ order.order_number, "Casey Customer", "Oxford Shirt", "12 MG Road", "1416.00", "pending" ].each do |text|
      assert_includes html, text
    end

    # The customer can see their own order.
    get "/api/v1/orders", headers: auth(token)
    assert_equal [ order.id ], response.parsed_body["data"]["data"].pluck("id")
  end

  test "guest checkout stores the guest's email and emails them" do
    perform_enqueued_jobs { place_order(nil, quantity: 1) }
    assert_response :created

    order = Order.last
    assert order.guest?
    assert_equal "casey@example.com", order.customer_email
    assert_equal [ "casey@example.com" ], ActionMailer::Base.deliveries.sole.to
  end

  test "admin status changes are validated, recorded, notified once and visible to the customer" do
    order = create_order_as(@customer)
    admin_token = login(@admin)
    perform_enqueued_jobs # send the confirmation first
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs do
      patch "/api/v1/orders/#{order.id}", params: { order: { status: "confirmed" } }, headers: auth(admin_token), as: :json
      assert_response :success
      # Repeating the same status is a no-op: no event, no second email.
      patch "/api/v1/orders/#{order.id}", params: { order: { status: "confirmed" } }, headers: auth(admin_token), as: :json
      assert_response :success
      patch "/api/v1/orders/#{order.id}", params: { order: { status: "shipped" } }, headers: auth(admin_token), as: :json
      assert_response :success
    end

    assert_equal(%w[confirmed shipped], ActionMailer::Base.deliveries.map { |m| m.subject[/(confirmed|shipped)/] })
    assert_equal %w[order_confirmation status_update:confirmed status_update:shipped],
                 order.notification_deliveries.order(:id).pluck(:event_key)
    assert order.notification_deliveries.all?(&:sent?)

    # Invalid transition is rejected and changes nothing.
    patch "/api/v1/orders/#{order.id}", params: { order: { status: "pending" } }, headers: auth(admin_token), as: :json
    assert_response :unprocessable_entity
    assert_equal "shipped", order.reload.status

    # Customer sees the updated status and timeline.
    get "/api/v1/orders/#{order.id}", headers: auth(login(@customer))
    body = response.parsed_body["data"]
    assert_equal "shipped", body["status"]
    assert_equal(%w[pending confirmed shipped], body["status_events"].pluck("to_status"))
  end

  test "duplicate notification requests never create or send duplicates" do
    order = create_order_as(@customer)
    perform_enqueued_jobs
    delivery = order.notification_deliveries.sole

    assert_nil OrderNotifier.queue_confirmation!(order), "unique index must block a second confirmation"
    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      NotificationDeliveryJob.perform_now(delivery.id) # already sent -> skipped
    end
    assert_equal 1, delivery.reload.attempts
  end

  test "failed notifications are recorded, retried automatically, and can be retried by an admin" do
    order = create_order_as(@customer)
    clear_enqueued_jobs
    delivery = order.notification_deliveries.sole

    with_unreachable_smtp do
      # Runs the job plus its automatic retries (3 attempts in total).
      perform_enqueued_jobs { NotificationDeliveryJob.perform_later(delivery.id) }
    end

    delivery.reload
    assert_equal "failed", delivery.status
    assert_equal 3, delivery.attempts
    assert_match(/Errno::ECONNREFUSED|Connection refused/, delivery.error_message)

    admin_token = login(@admin)
    get "/api/v1/automation/notifications/summary", headers: auth(admin_token)
    assert_equal 1, response.parsed_body["data"]["failed"]

    perform_enqueued_jobs do
      post "/api/v1/automation/notifications/#{delivery.id}/retry", headers: auth(admin_token)
      assert_response :success
    end
    assert_equal "sent", delivery.reload.status
    assert_nil delivery.error_message
    assert_equal 1, ActionMailer::Base.deliveries.size

    # A sent notification cannot be retried again.
    post "/api/v1/automation/notifications/#{delivery.id}/retry", headers: auth(admin_token)
    assert_response :unprocessable_entity
  end

  test "cancelling restores inventory, for both customer cancel and admin status change" do
    order = create_order_as(@customer, quantity: 3)
    assert_equal 7, @variant.reload.stock

    patch "/api/v1/orders/#{order.id}/cancel", headers: auth(login(@customer))
    assert_response :success
    assert_equal "cancelled", order.reload.status
    assert_equal 10, @variant.reload.stock
    assert order.notification_deliveries.exists?(event_key: "status_update:cancelled")

    # Admin cancelling a confirmed order through the status update endpoint.
    second_order = create_order_as(@customer, quantity: 4)
    admin_token = login(@admin)
    patch "/api/v1/orders/#{second_order.id}", params: { order: { status: "confirmed" } }, headers: auth(admin_token), as: :json
    patch "/api/v1/orders/#{second_order.id}", params: { order: { status: "cancelled" } }, headers: auth(admin_token), as: :json
    assert_response :success
    assert_equal 10, @variant.reload.stock

    # Cancelling twice does not restore stock twice.
    patch "/api/v1/orders/#{second_order.id}", params: { order: { status: "cancelled" } }, headers: auth(admin_token), as: :json
    assert_equal 10, @variant.reload.stock
  end

  test "customers cannot change payment status, order status, or their own role" do
    order = create_order_as(@customer)
    token = login(@customer)

    patch "/api/v1/orders/#{order.id}", params: { order: { payment_status: "paid" } }, headers: auth(token), as: :json
    assert_response :forbidden
    assert_equal "unpaid", order.reload.payment_status

    patch "/api/v1/users/#{@customer.id}", params: { user: { role: "admin", name: "New Name" } }, headers: auth(token), as: :json
    assert_response :success
    assert_equal [ "customer", "New Name" ], [ @customer.reload.role, @customer.name ]

    post "/api/v1/signup", params: { user: { email_address: "new@example.com", password: "secret123",
                                             password_confirmation: "secret123", role: "admin", } }, as: :json
    assert_response :created
    assert_equal "customer", User.find_by(email_address: "new@example.com").role

    get "/api/v1/automation/notifications", headers: auth(token)
    assert_response :forbidden
  end

  private

  def login(user)
    post "/api/v1/login", params: { identifier: user.email_address, password: "password123" }, as: :json
    assert_response :success
    response.parsed_body["token"]
  end

  def auth(token)
    token ? { "Authorization" => "Bearer #{token}" } : {}
  end

  def place_order(token, quantity:)
    post "/api/v1/orders",
         params: {
           order: { tax: 1, shipping_fee: -500, shipping_address: ADDRESS },
           items: [ { product_id: @product.id, product_variant_id: @variant.id, quantity: quantity } ],
         },
         headers: auth(token), as: :json
  end

  def create_order_as(user, quantity: 1)
    place_order(login(user), quantity: quantity)
    assert_response :created
    Order.find(response.parsed_body["data"]["id"])
  end

  # Real SMTP failure: nothing listens on port 1.
  def with_unreachable_smtp
    original = [ ActionMailer::Base.delivery_method, ActionMailer::Base.smtp_settings ]
    ActionMailer::Base.delivery_method = :smtp
    ActionMailer::Base.smtp_settings = { address: "127.0.0.1", port: 1 }
    yield
  ensure
    ActionMailer::Base.delivery_method, ActionMailer::Base.smtp_settings = original
  end
end
