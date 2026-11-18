# Admin-only API behind the Automation dashboard: delivery records, stats, details and retry.
module Api
  module V1
    module Automation
      class NotificationsController < ApplicationController
        include ResponseRenderingConcern

        before_action :require_admin!
        before_action :set_delivery, only: %i[show resend]

        # GET /api/v1/automation/notifications?status=&kind=&order_id=&search=&page=&per_page=
        def index
          scope = deliveries.includes(:order_status_event, order: :user).recent_first
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where(kind: params[:kind]) if params[:kind].present?
          scope = scope.where(order_id: params[:order_id]) if params[:order_id].present?
          if params[:search].present?
            term = "%#{NotificationDelivery.sanitize_sql_like(params[:search].strip)}%"
            scope = scope.where("orders.order_number ILIKE :t OR notification_deliveries.recipient ILIKE :t OR orders.customer_name ILIKE :t", t: term)
          end

          records = scope.paginate(page: params[:page] || 1, per_page: [ (params[:per_page] || 10).to_i, 100 ].min)

          render_success(
            {
              data: NotificationDeliveryBlueprint.render_as_json(records),
              meta: {
                current_page: records.current_page,
                per_page: records.per_page,
                total_pages: records.total_pages,
                total_count: records.total_entries,
              },
            }
          )
        end

        # GET /api/v1/automation/notifications/summary
        def summary
          counts = deliveries.group(:status).count
          render_success(
            {
              total: counts.values.sum,
              sent: counts.fetch("sent", 0),
              failed: counts.fetch("failed", 0),
              pending: counts.fetch("pending", 0) + counts.fetch("sending", 0),
              by_kind: deliveries.group(:kind).count,
              last_sent_at: deliveries.where(status: "sent").maximum(:sent_at),
            }
          )
        end

        # GET /api/v1/automation/notifications/:id  (includes a rendered email preview)
        def show
          payload = NotificationDeliveryBlueprint.render_as_hash(@delivery)
          payload[:preview] = email_preview(@delivery)
          payload[:order_status_events] = OrderStatusEventBlueprint.render_as_hash(@delivery.order.status_events)
          render_success(payload)
        end

        # POST /api/v1/automation/notifications/:id/retry
        def resend
          unless @delivery.retryable?
            return render_error("common.operation_failed",
                                "Only failed or stuck notifications can be retried (current status: #{@delivery.status})",
                                :unprocessable_entity)
          end

          @delivery.update!(status: "pending", error_message: nil)
          NotificationDeliveryJob.perform_later(@delivery.id)
          render_success(NotificationDeliveryBlueprint.render_as_hash(@delivery.reload), nil, "Notification re-queued for delivery")
        end

        private

        def require_admin!
          return if current_user&.admin?

          render json: { success: false, error: "Forbidden" }, status: :forbidden
        end

        def deliveries
          NotificationDelivery.for_org(current_user.org_id)
        end

        def set_delivery
          @delivery = deliveries.find_by(id: params[:id])
          render_error("common.not_found", "Notification not found", :not_found) unless @delivery
        end

        def email_preview(delivery)
          message = delivery.build_message
          {
            subject: message.subject,
            to: Array(message.to),
            from: Array(message.from),
            html: (message.html_part || message).body.decoded,
            text: message.text_part&.body&.decoded,
          }
        rescue StandardError => e
          { error: "#{e.class}: #{e.message}" }
        end
      end
    end
  end
end
