class OrderBlueprint < Blueprinter::Base
  identifier :id

  fields :order_number, :status, :payment_status, :subtotal, :tax, :shipping_fee, :total,
         :customer_name, :customer_email, :created_at, :updated_at
  field :shipping_address do |order|
    order.shipping_address_hash
  end

  association :user, blueprint: UserBlueprint
  association :order_items, blueprint: OrderItemBlueprint
  association :status_events, blueprint: OrderStatusEventBlueprint
end
