# app/controllers/api/v1/orders_controller.rb
module Api
  module V1
    class OrdersController < ApplicationController
      include Authorization
      include ResponseRenderingConcern

      allow_unauthenticated_access only: [:create]
      # Checkout stays open to guests, but a valid bearer token must still identify the customer.
      before_action :authenticate_with_token, only: [:create]
      load_and_authorize_resource
      skip_load_and_authorize_resource only: [:create]

      def index
        orders = Order.accessible_by(current_ability)
                      .includes(:user, :status_events, order_items: :product)
                      .order(created_at: :desc)
                      .paginate(page: params[:page] || 1, per_page: params[:per_page] || 10)

        render_success(
          {
            data: OrderBlueprint.render_as_json(orders),
            meta: {
              current_page: orders.current_page,
              per_page: orders.per_page,
              total_pages: orders.total_pages,
              total_count: orders.total_entries,
            },
          }
        )
      end

      def show
        render_success(OrderBlueprint.render_as_json(@order))
      end

      def create
        @order = Order.new(order_params)
        assign_order_owner!

        unless @order.user && @order.organization
          @order.errors.add(:base, "Unable to determine order owner")
          return handle_response(@order)
        end

        if current_user.blank? && guest_shipping_address.blank?
          @order.errors.add(:base, "Shipping address is required for guest checkout")
          return handle_response(@order)
        end

        @order.shipping_address = serialize_address(guest_shipping_address || {})
        assign_customer_contact!
        confirmation = nil

        ActiveRecord::Base.transaction do
          items = params[:items]

          if items.blank?
            @order.errors.add(:base, "Items required")
            raise ActiveRecord::Rollback
          end

          items.each do |item|
            product = Product.find_by(id: item[:product_id])
            unless product
              @order.errors.add(:base, "Product not found")
              raise ActiveRecord::Rollback
            end

            if product.org_id != @order.org_id
              @order.errors.add(:base, "All items must belong to the same store")
              raise ActiveRecord::Rollback
            end

            variant = product.variants.find_by(id: item[:product_variant_id])
            unless variant
              @order.errors.add(:base, "Variant not found")
              raise ActiveRecord::Rollback
            end

            qty = item[:quantity].to_i

            if qty < 1
              @order.errors.add(:base, "Invalid quantity")
              raise ActiveRecord::Rollback
            end

            variant.lock!

            if qty > variant.stock
              @order.errors.add(:base, "Only #{variant.stock} items available")
              raise ActiveRecord::Rollback
            end

            variant.update!(stock: variant.stock - qty)

            @order.order_items.build(
              product_id: product.id,
              product_variant_id: variant.id,
              product_name: product.name,
              price: variant.price,
              quantity: qty
            )
          end

          unless @order.save
            raise ActiveRecord::Rollback
          end

          @order.status_events.create!(from_status: nil, to_status: @order.status, changed_by: current_user)
          confirmation = OrderNotifier.queue_confirmation!(@order)
        end

        if @order.persisted?
          # Transaction committed: now it is safe to enqueue the confirmation email.
          OrderNotifier.dispatch(confirmation)

          # Clear the customer's cart after a successful order
          current_user.cart&.cart_items&.destroy_all if current_user && @order.user_id == current_user.id

          render_success(
            OrderBlueprint.render_as_json(@order),
            "common.created",
            nil,
            :created
          )
        else
          handle_response(@order)
        end
      end

      def update
        attrs = update_params

        if attrs.key?(:status) && attrs[:status].present?
          result = Orders::TransitionStatus.call(order: @order, to: attrs[:status], actor: current_user)
          return render_error("common.operation_failed", result.error, :unprocessable_entity) unless result.success?
        end

        if attrs.key?(:payment_status) && !@order.update(payment_status: attrs[:payment_status])
          return handle_response(@order)
        end

        render_success(OrderBlueprint.render_as_json(@order.reload), "common.updated")
      end

      def cancel
        order = Order.accessible_by(current_ability).find(params[:id])

        unless order.status == "pending"
          return render_error(
            "common.operation_failed",
            "Order cannot be cancelled unless it is pending",
            :unprocessable_entity
          )
        end

        result = Orders::TransitionStatus.call(order: order, to: "cancelled", actor: current_user)
        return render_error("common.operation_failed", result.error, :unprocessable_entity) unless result.success?

        render_success(OrderBlueprint.render_as_json(order.reload), "order_cancelled")
      end

      private

      def order_params
        params.require(:order).permit(
          :shipping_fee,
          :tax,
          shipping_address: %i[full_name email phone address city state zip_code]
        )
      end

      def update_params
        params.require(:order).permit(:status, :payment_status)
      end
      def build_items
        items = params[:items]

        if items.blank?
          @order.errors.add(:base, "Items required")
          return false
        end

        items.each do |item|
          product = Product.find_by(id: item[:product_id])
          return false unless product

          variant = product.variants.find_by(id: item[:product_variant_id])
          return false unless variant

          quantity = item[:quantity].to_i
          return false if quantity < 1

          if quantity > variant.stock
            @order.errors.add(:base, "Only #{variant.stock} items available for #{product.name}")
            return false
          end

          @order.order_items.build(
            product_id: product.id,
            product_variant_id: variant.id,
            price: variant.price,
            quantity: quantity
          )
        end

        true
      end

      def assign_order_owner!
        owner = admin_selected_customer || current_user || guest_checkout_user
        return unless owner

        @order.organization = owner.organization
        @order.user = owner
      end

      # Admin "Add Order" sends order[user_id]: place the order on behalf of that customer.
      def admin_selected_customer
        user_id = params.dig(:order, :user_id)
        return if user_id.blank? || !current_user&.admin?

        User.find_by(id: user_id, org_id: current_user.org_id)
      end

      # Email/name used for notifications. Checkout form values win; account values are the fallback.
      def assign_customer_contact!
        address = guest_shipping_address
        owner = @order.user
        account_email = owner.email_address unless @order.guest?

        @order.customer_email = address["email"].presence&.strip&.downcase || account_email
        @order.customer_name = address["full_name"].presence || (owner.name unless @order.guest?)
      end

      def guest_checkout_user
        return @guest_checkout_user if defined?(@guest_checkout_user)

        organization = guest_checkout_organization
        return @guest_checkout_user = nil unless organization

        guest_email = "guest-orders+#{organization.slug}@example.local"

        @guest_checkout_user = User.find_or_create_by!(email_address: guest_email) do |user|
          generated_password = SecureRandom.hex(16)
          user.password = generated_password
          user.password_confirmation = generated_password
          user.role = :customer
          user.organization = organization
          user.name = "#{organization.name} Guest Checkout"
        end
      end

      def guest_checkout_organization
        @guest_checkout_organization ||= begin
          first_item = Array(params[:items]).first
          product = Product.find_by(id: first_item&.[](:product_id) || first_item&.[]("product_id"))
          product&.organization
        end
      end

      def guest_shipping_address
        shipping_address = order_params[:shipping_address]
        shipping_address.respond_to?(:to_h) ? shipping_address.to_h.stringify_keys : {}
      end

      def serialize_address(address)
        address.to_json
      end
    end
  end
end
