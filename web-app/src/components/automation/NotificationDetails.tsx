import { AlertTriangle, Mail, RotateCcw, ShoppingBag } from "lucide-react";
import { useNotificationDetails } from "../../hooks/useAutomation";
import DeliveryStatusBadge from "./DeliveryStatusBadge";
import OrderStatusTimeline from "../orders/OrderStatusTimeline";
import Button from "../ui/Button";

interface Props {
    id: number;
    onRetry: (id: number) => void;
    onInspectOrder: (orderId: number) => void;
    isRetrying?: boolean;
}

const fmt = (iso?: string | null) => (iso ? new Date(iso).toLocaleString() : "—");

export default function NotificationDetails({ id, onRetry, onInspectOrder, isRetrying }: Props) {
    const { data, isLoading, isError } = useNotificationDetails(id);

    if (isLoading) {
        return <div className="py-16 text-center text-sm text-neutral-500">Loading notification…</div>;
    }
    if (isError || !data) {
        return <div className="py-16 text-center text-sm text-red-600">Could not load this notification.</div>;
    }

    const rows: [string, React.ReactNode][] = [
        ["Automation", data.kind === "order_confirmation" ? "Order confirmation email" : "Order status notification"],
        ["Triggered by", data.event_label],
        ["Recipient", data.recipient ?? "—"],
        ["Subject", data.subject ?? data.preview?.subject ?? "—"],
        ["Attempts", data.attempts],
        ["Queued at", fmt(data.created_at)],
        ["Last attempt", fmt(data.last_attempted_at)],
        ["Delivered at", fmt(data.sent_at)],
    ];

    return (
        <div className="space-y-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex items-center gap-3">
                    <DeliveryStatusBadge status={data.status} />
                    <span className="text-sm text-neutral-500">
                        Order <span className="font-semibold text-neutral-900">{data.order.order_number}</span>
                    </span>
                </div>
                <div className="flex gap-2">
                    <Button size="sm" variant="outline" onClick={() => onInspectOrder(data.order.id)}>
                        <ShoppingBag className="w-4 h-4 mr-1.5" /> Inspect order
                    </Button>
                    {data.retryable && (
                        <Button size="sm" onClick={() => onRetry(data.id)} isLoading={isRetrying} disabled={isRetrying}>
                            <RotateCcw className="w-4 h-4 mr-1.5" /> Retry delivery
                        </Button>
                    )}
                </div>
            </div>

            {data.error_message && (
                <div className="flex gap-3 rounded-2xl border border-red-100 bg-red-50 p-4 text-sm text-red-700">
                    <AlertTriangle className="w-5 h-5 shrink-0" />
                    <div>
                        <p className="font-bold">Last delivery error</p>
                        <p className="mt-1 break-words font-mono text-xs">{data.error_message}</p>
                    </div>
                </div>
            )}

            <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-8 gap-y-3 rounded-2xl border border-neutral-100 p-5">
                {rows.map(([label, value]) => (
                    <div key={label} className="min-w-0">
                        <dt className="text-xs font-semibold uppercase tracking-wider text-neutral-400">{label}</dt>
                        <dd className="mt-0.5 text-sm font-medium text-neutral-900 break-words">{value}</dd>
                    </div>
                ))}
            </dl>

            <div>
                <h3 className="text-sm font-semibold text-neutral-900 mb-3">Order timeline</h3>
                <OrderStatusTimeline status={data.order.status} events={data.order_status_events} />
            </div>

            <div>
                <h3 className="text-sm font-semibold text-neutral-900 mb-3 flex items-center gap-2">
                    <Mail className="w-4 h-4" /> Email preview
                </h3>
                {data.preview?.html ? (
                    <iframe
                        title="Email preview"
                        sandbox=""
                        srcDoc={data.preview.html}
                        className="w-full h-[520px] rounded-2xl border border-neutral-200 bg-white"
                    />
                ) : (
                    <p className="text-sm text-neutral-500">{data.preview?.error ?? "No preview available."}</p>
                )}
            </div>
        </div>
    );
}
