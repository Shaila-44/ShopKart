import { apiService } from "./apiService";
import type { OrderStatusEvent } from "./order";

export type DeliveryStatus = "pending" | "sending" | "sent" | "failed";
export type NotificationKind = "order_confirmation" | "status_update";

export interface NotificationDelivery {
    id: number;
    kind: NotificationKind;
    event_key: string;
    event_label: string;
    trigger_status: string;
    status: DeliveryStatus;
    recipient: string | null;
    subject: string | null;
    attempts: number;
    error_message: string | null;
    sent_at: string | null;
    last_attempted_at: string | null;
    created_at: string;
    updated_at: string;
    retryable: boolean;
    order: {
        id: number;
        order_number: string;
        status: string;
        total: string | number;
        customer_name: string | null;
        customer_email: string | null;
    };
}

export interface NotificationDetails extends NotificationDelivery {
    preview: {
        subject?: string;
        to?: string[];
        from?: string[];
        html?: string;
        text?: string | null;
        error?: string;
    };
    order_status_events: OrderStatusEvent[];
}

export interface AutomationSummary {
    total: number;
    sent: number;
    failed: number;
    pending: number;
    by_kind: Partial<Record<NotificationKind, number>>;
    last_sent_at: string | null;
}

export interface NotificationListParams {
    page?: number;
    per_page?: number;
    status?: string;
    kind?: string;
    order_id?: number;
    search?: string;
}

export interface PaginatedNotifications {
    data: NotificationDelivery[];
    meta: { current_page: number; per_page: number; total_pages: number; total_count: number };
}

const BASE_PATH = "/automation/notifications";

const AutomationAPI = {
    summary() {
        return apiService.get<AutomationSummary>(`${BASE_PATH}/summary`);
    },
    list(params?: NotificationListParams) {
        return apiService.get<PaginatedNotifications>(BASE_PATH, params);
    },
    get(id: number) {
        return apiService.get<NotificationDetails>(`${BASE_PATH}/${id}`);
    },
    retry(id: number) {
        return apiService.post<NotificationDelivery>(`${BASE_PATH}/${id}/retry`);
    },
};

export default AutomationAPI;
