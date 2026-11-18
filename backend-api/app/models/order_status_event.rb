class OrderStatusEvent < ApplicationRecord
  belongs_to :order
  belongs_to :changed_by, class_name: "User", optional: true

  validates :to_status, inclusion: { in: Order::STATUSES }
end
