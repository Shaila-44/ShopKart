import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import AutomationAPI, { NotificationListParams } from "../api/automation";

// Delivery status changes asynchronously (background job), so the dashboard polls.
const LIVE_REFRESH_MS = 5000;

export const useAutomationSummary = () =>
    useQuery({
        queryKey: ["automation", "summary"],
        queryFn: async () => {
            const res = await AutomationAPI.summary();
            return res.data!;
        },
        refetchInterval: LIVE_REFRESH_MS,
    });

export const useNotifications = (params: NotificationListParams, options: { enabled?: boolean } = {}) =>
    useQuery({
        queryKey: ["automation", "notifications", params],
        queryFn: async () => {
            const res = await AutomationAPI.list(params);
            return {
                data: res.data?.data ?? [],
                meta: res.data?.meta ?? { current_page: 1, per_page: params.per_page ?? 10, total_pages: 1, total_count: 0 },
            };
        },
        refetchInterval: LIVE_REFRESH_MS,
        enabled: options.enabled ?? true,
    });

export const useNotificationDetails = (id: number | null) =>
    useQuery({
        queryKey: ["automation", "notification", id],
        queryFn: async () => {
            const res = await AutomationAPI.get(id!);
            return res.data!;
        },
        enabled: !!id,
        refetchInterval: LIVE_REFRESH_MS,
    });

export const useRetryNotification = () => {
    const queryClient = useQueryClient();
    return useMutation({
        mutationFn: async (id: number) => {
            const res = await AutomationAPI.retry(id);
            return res.data!;
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ["automation"] });
        },
    });
};
