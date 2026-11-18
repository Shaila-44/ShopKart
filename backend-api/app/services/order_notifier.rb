# Creates NotificationDelivery records (inside the caller's transaction) and enqueues the
# delivery job (after the transaction has committed).
#
# Duplicate protection: notification_deliveries has a unique index on (order_id, event_key),
# so an order can only ever have one confirmation and one notification per status.
class OrderNotifier
  NOTIFIABLE_STATUSES = %w[confirmed shipped delivered cancelled].freeze

  class << self
    def queue_confirmation!(order)
      create_delivery(order, kind: "order_confirmation", event_key: "order_confirmation")
    end

    def queue_status_update!(order, event)
      return unless NOTIFIABLE_STATUSES.include?(event.to_status)

      create_delivery(
        order,
        kind: "status_update",
        event_key: "status_update:#{event.to_status}",
        order_status_event: event
      )
    end

    # Call only after the surrounding transaction has committed.
    def dispatch(*deliveries)
      deliveries.flatten.compact.each do |delivery|
        NotificationDeliveryJob.perform_later(delivery.id)
      end
    end

    private

    def create_delivery(order, kind:, event_key:, order_status_event: nil)
      # A savepoint keeps a unique-index violation from aborting the outer transaction.
      NotificationDelivery.transaction(requires_new: true) do
        NotificationDelivery.create!(
          order: order,
          kind: kind,
          event_key: event_key,
          order_status_event: order_status_event,
          recipient: order.notification_email,
          status: "pending"
        )
      end
    rescue ActiveRecord::RecordNotUnique
      nil # lost a race: another request already queued this notification
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.errors.of_kind?(:event_key, :taken)

      nil # already queued for this order/event
    end
  end
end
