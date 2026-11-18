# Sends one NotificationDelivery and records the result on the row.
#
# * Idempotent: the row is "claimed" with an atomic UPDATE, so two workers (or an automatic
#   retry and a manual re-send) can never both send it, and a sent row is never sent again.
# * Failures are recorded (status "failed", error_message, attempts) and re-raised so Active Job
#   retries automatically; admins can also re-queue failed rows from the Automation dashboard.
class NotificationDeliveryJob < ApplicationJob
  queue_as :mailers

  # After the last automatic attempt the failure stays recorded on the delivery row
  # (status "failed" + error_message), where admins can see it and retry it manually.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    Rails.logger.warn("[NotificationDeliveryJob] giving up on delivery #{job.arguments.first}: #{error.class}: #{error.message}")
  end
  discard_on ActiveRecord::RecordNotFound

  def perform(delivery_id)
    delivery = NotificationDelivery.find(delivery_id)
    return unless claim(delivery)

    begin
      message = delivery.build_message
      raise ArgumentError, "No recipient email address for order #{delivery.order.order_number}" if message.to.blank?

      message.deliver_now
      delivery.update!(status: "sent", sent_at: Time.current, subject: message.subject,
                       recipient: Array(message.to).join(", "), error_message: nil)
    rescue StandardError => e
      delivery.update_columns(status: "failed", error_message: "#{e.class}: #{e.message}".truncate(1_000),
                              updated_at: Time.current)
      raise
    end
  end

  private

  def claim(delivery)
    now = Time.current
    claimed = NotificationDelivery
              .where(id: delivery.id)
              .where("status IN ('pending', 'failed') OR (status = 'sending' AND last_attempted_at < ?)", 5.minutes.ago)
              .update_all(["status = 'sending', attempts = attempts + 1, last_attempted_at = ?, updated_at = ?", now, now])
    delivery.reload if claimed.positive?
    claimed.positive?
  end
end
