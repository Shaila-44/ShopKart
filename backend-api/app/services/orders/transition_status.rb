# Single entry point for every order status change (admin update and customer cancel).
#
# Inside one transaction it: locks the order, validates the transition, restores stock
# when cancelling, persists the new status, records an OrderStatusEvent and creates the
# matching NotificationDelivery row. The notification job is enqueued only after commit.
module Orders
  class TransitionStatus
    TRANSITIONS = {
      "pending" => %w[confirmed cancelled],
      "confirmed" => %w[shipped cancelled],
      "shipped" => %w[delivered],
      "delivered" => [],
      "cancelled" => [],
    }.freeze

    class InvalidTransition < StandardError; end

    Result = Struct.new(:success, :changed, :order, :event, :error, keyword_init: true) do
      def success? = success
      def changed? = changed
    end

    def self.call(...) = new(...).call

    def self.allowed?(from, to)
      TRANSITIONS.fetch(from.to_s, []).include?(to.to_s)
    end

    def initialize(order:, to:, actor: nil, note: nil)
      @order = order
      @to = to.to_s
      @actor = actor
      @note = note
    end

    def call
      unless Order::STATUSES.include?(@to)
        return Result.new(success: false, changed: false, order: @order, error: "Unknown order status '#{@to}'")
      end

      event = nil
      delivery = nil

      Order.transaction do
        @order.lock!
        from = @order.status

        if from != @to
          raise InvalidTransition, "Cannot change order status from #{from} to #{@to}" unless self.class.allowed?(from, @to)

          restore_stock! if @to == "cancelled"
          @order.update!(status: @to)
          event = @order.status_events.create!(from_status: from, to_status: @to, changed_by: @actor, note: @note)
          delivery = OrderNotifier.queue_status_update!(@order, event)
        end
      end

      # Runs after COMMIT, so the job always sees the persisted status.
      OrderNotifier.dispatch(delivery)

      Result.new(success: true, changed: event.present?, order: @order, event: event)
    rescue InvalidTransition => e
      Result.new(success: false, changed: false, order: @order.reload, error: e.message)
    end

    private

    # Atomic SQL increment so concurrent cancels/orders cannot lose updates.
    def restore_stock!
      @order.order_items.where.not(product_variant_id: nil).order(:product_variant_id).each do |item|
        ProductVariant.where(id: item.product_variant_id).update_all(["stock = stock + ?", item.quantity])
      end
    end
  end
end
