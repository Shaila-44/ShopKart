class AddCustomerContactToOrders < ActiveRecord::Migration[8.0]
  def up
    add_column :orders, :customer_email, :string
    add_column :orders, :customer_name, :string
    add_index :orders, :user_id unless index_exists?(:orders, :user_id)
    add_index :orders, :org_id unless index_exists?(:orders, :org_id)

    # Backfill existing orders from the checkout address (JSON text) or the owning account.
    select_rows(<<~SQL).each do |id, address, email, name|
      SELECT orders.id, orders.shipping_address, users.email_address, users.name
      FROM orders JOIN users ON users.id = orders.user_id
    SQL
      parsed = begin
        JSON.parse(address.presence || "{}")
      rescue JSON::ParserError
        {}
      end
      guest = email.to_s.match?(/\Aguest-orders\+.*@example\.local\z/)
      customer_email = parsed["email"].presence || (email unless guest)
      customer_name = parsed["full_name"].presence || (name unless guest)
      execute(sanitize_sql(["UPDATE orders SET customer_email = ?, customer_name = ? WHERE id = ?", customer_email, customer_name, id]))
    end
  end

  def down
    remove_index :orders, :user_id, if_exists: true
    remove_index :orders, :org_id, if_exists: true
    remove_column :orders, :customer_name
    remove_column :orders, :customer_email
  end

  private

  def sanitize_sql(args)
    ActiveRecord::Base.sanitize_sql_array(args)
  end
end
