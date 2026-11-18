class NotificationDelivery < ApplicationRecord
  KINDS = %w[order_confirmation status_update].freeze
  STATUSES = %w[pending sending sent failed].freeze
  RETRYABLE_STATUSES = %w[pending failed].freeze

  belongs_to :order
  belongs_to :order_status_event, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :event_key, presence: true, uniqueness: { scope: :order_id }

  scope :for_org, ->(org_id) { joins(:order).where(orders: { org_id: org_id }) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def sent? = status == "sent"
  def failed? = status == "failed"

  def retryable?
    RETRYABLE_STATUSES.include?(status) || (status == "sending" && last_attempted_at.to_i < 5.minutes.ago.to_i)
  end

  # The status this notification announces ("pending" for the confirmation email).
  def trigger_status
    order_status_event&.to_status || "pending"
  end

  def event_label
    kind == "order_confirmation" ? "Order placed" : "Status → #{trigger_status.capitalize}"
  end

  # Builds (but does not deliver) the Mail::Message for this record.
  def build_message
    mailer = OrderMailer.with(order: order, recipient: recipient, event: order_status_event)
    kind == "order_confirmation" ? mailer.confirmation : mailer.status_update
  end
end
