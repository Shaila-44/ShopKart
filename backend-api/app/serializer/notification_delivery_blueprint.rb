class NotificationDeliveryBlueprint < Blueprinter::Base
  identifier :id

  fields :kind, :event_key, :status, :recipient, :subject, :attempts, :error_message,
         :sent_at, :last_attempted_at, :created_at, :updated_at

  field(:event_label) { |delivery| delivery.event_label }
  field(:trigger_status) { |delivery| delivery.trigger_status }
  field(:retryable) { |delivery| delivery.retryable? }

  field :order do |delivery|
    order = delivery.order
    {
      id: order.id,
      order_number: order.order_number,
      status: order.status,
      total: order.total,
      customer_name: order.customer_name.presence || (order.user&.name unless order.guest?),
      customer_email: order.notification_email,
    }
  end
end
