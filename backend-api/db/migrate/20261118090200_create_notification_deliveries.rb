class CreateNotificationDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_deliveries do |t|
      t.references :order, null: false, foreign_key: true
      t.references :order_status_event, foreign_key: true
      t.string :kind, null: false
      # One notification per (order, event_key): e.g. "order_confirmation", "status_update:shipped"
      t.string :event_key, null: false
      t.string :status, null: false, default: "pending"
      t.string :recipient
      t.string :subject
      t.integer :attempts, null: false, default: 0
      t.text :error_message
      t.datetime :last_attempted_at
      t.datetime :sent_at
      t.timestamps
    end
    add_index :notification_deliveries, [:order_id, :event_key], unique: true
    add_index :notification_deliveries, [:status, :created_at]
  end
end
