class OrderStatusEventBlueprint < Blueprinter::Base
  identifier :id

  fields :from_status, :to_status, :note, :created_at

  field :changed_by_name do |event|
    event.changed_by&.name
  end
end
