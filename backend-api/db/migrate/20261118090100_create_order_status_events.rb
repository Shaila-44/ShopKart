class CreateOrderStatusEvents < ActiveRecord::Migration[8.0]
  def up
    create_table :order_status_events do |t|
      t.references :order, null: false, foreign_key: true
      t.string :from_status
      t.string :to_status, null: false
      t.references :changed_by, foreign_key: { to_table: :users }
      t.string :note
      t.datetime :created_at, null: false
    end
    add_index :order_status_events, [:order_id, :created_at]

    # Seed the timeline of existing orders with their creation event.
    execute <<~SQL
      INSERT INTO order_status_events (order_id, from_status, to_status, created_at)
      SELECT id, NULL, 'pending', created_at FROM orders
    SQL
    execute <<~SQL
      INSERT INTO order_status_events (order_id, from_status, to_status, created_at)
      SELECT id, 'pending', status, updated_at FROM orders WHERE status IS NOT NULL AND status <> 'pending'
    SQL
  end

  def down
    drop_table :order_status_events
  end
end
