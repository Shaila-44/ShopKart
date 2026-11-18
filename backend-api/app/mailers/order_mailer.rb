class OrderMailer < ApplicationMailer
  helper :order_mailer

  STATUS_COPY = {
    "confirmed" => { subject: "is confirmed", headline: "Your order is confirmed",
                     body: "Good news: we've confirmed your order and are getting it ready to ship.", },
    "shipped" => { subject: "has shipped", headline: "Your order is on its way",
                   body: "Your order has left our warehouse and is on its way to you.", },
    "delivered" => { subject: "was delivered", headline: "Your order was delivered",
                     body: "Your order has been delivered. We hope you love it!", },
    "cancelled" => { subject: "was cancelled", headline: "Your order was cancelled",
                     body: "Your order has been cancelled and the items have been released. " \
                           "If you already paid, the refund will go back to your original payment method.", },
  }.freeze

  TIMELINE = %w[pending confirmed shipped delivered].freeze

  before_action :load_order

  def confirmation
    mail to: @recipient, subject: "#{@shop_name}: order #{@order.order_number} received. Thank you!"
  end

  def status_update
    @status = params[:event]&.to_status || @order.status
    @copy = STATUS_COPY.fetch(@status) { { subject: "was updated", headline: "Your order was updated", body: "" } }
    @timeline = TIMELINE
    mail to: @recipient, subject: "#{@shop_name}: order #{@order.order_number} #{@copy[:subject]}"
  end

  private

  def load_order
    @order = params[:order]
    @recipient = params[:recipient].presence || @order.notification_email
    @customer_name = @order.customer_name.presence || "there"
    @address = @order.shipping_address_hash
    @items = @order.order_items.to_a
    @shop_name = Rails.configuration.x.shop_name
    @orders_url = "#{Rails.configuration.client_url}/profile?tab=orders"
  end
end
