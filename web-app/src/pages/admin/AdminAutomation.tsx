import { useEffect, useState } from "react";
import { toast } from "react-toastify";
import {
    AlertTriangle, CheckCircle2, Clock, Eye, Mail, RotateCcw, Search, ShoppingBag, Zap,
} from "lucide-react";
import Card from "../../components/ui/Card";
import Modal from "../../components/ui/Modal";
import { TableRowSkeleton } from "../../components/ui/Skeleton";
import DeliveryStatusBadge from "../../components/automation/DeliveryStatusBadge";
import NotificationDetails from "../../components/automation/NotificationDetails";
import OrderDetailsModal from "../../components/orders/OrderDetailsModal";
import { useAutomationSummary, useNotifications, useRetryNotification } from "../../hooks/useAutomation";
import { useOrder, useUpdateOrder } from "../../hooks/useOrder";
import type { Order } from "../../api/order";

const STATUS_FILTERS = [
    { value: "", label: "All" },
    { value: "sent", label: "Sent" },
    { value: "failed", label: "Failed" },
    { value: "pending", label: "Pending" },
] as const;

const KIND_LABELS: Record<string, string> = {
    order_confirmation: "Order confirmation",
    status_update: "Status notification",
};

const formatTime = (iso?: string | null) =>
    iso ? new Date(iso).toLocaleString("en-IN", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) : "—";

export default function AdminAutomation() {
    const [page, setPage] = useState(1);
    const [statusFilter, setStatusFilter] = useState("");
    const [searchInput, setSearchInput] = useState("");
    const [search, setSearch] = useState("");
    const [detailsId, setDetailsId] = useState<number | null>(null);
    const [inspectOrderId, setInspectOrderId] = useState<number | null>(null);
    const perPage = 10;

    // Debounce the search box.
    useEffect(() => {
        const t = setTimeout(() => {
            setSearch(searchInput.trim());
            setPage(1);
        }, 350);
        return () => clearTimeout(t);
    }, [searchInput]);

    const { data: summary, isLoading: summaryLoading } = useAutomationSummary();
    const { data, isLoading, isFetching } = useNotifications({
        page,
        per_page: perPage,
        status: statusFilter || undefined,
        search: search || undefined,
    });
    const retryMutation = useRetryNotification();

    const rows = data?.data ?? [];
    const meta = data?.meta;

    const handleRetry = async (id: number) => {
        try {
            await retryMutation.mutateAsync(id);
            toast.success("Notification re-queued. Delivery status will update shortly.");
        } catch (error: any) {
            toast.error(error?.message || "Retry failed");
        }
    };

    const stats = [
        { label: "Total notifications", value: summary?.total, icon: Zap, accent: "from-indigo-500 to-indigo-400", tint: "bg-indigo-50 text-indigo-600", filter: "" },
        { label: "Sent", value: summary?.sent, icon: CheckCircle2, accent: "from-emerald-500 to-emerald-400", tint: "bg-emerald-50 text-emerald-600", filter: "sent" },
        { label: "Failed", value: summary?.failed, icon: AlertTriangle, accent: "from-red-500 to-red-400", tint: "bg-red-50 text-red-600", filter: "failed" },
        { label: "Pending", value: summary?.pending, icon: Clock, accent: "from-amber-500 to-amber-400", tint: "bg-amber-50 text-amber-600", filter: "pending" },
    ];

    return (
        <div className="space-y-6">
            <div className="flex flex-col sm:flex-row sm:items-end justify-between gap-4">
                <div>
                    <h1 className="text-3xl font-display font-bold text-neutral-900 tracking-tight">Automation</h1>
                    <p className="text-sm text-neutral-500 mt-1">
                        Order emails sent automatically by background jobs: confirmations and status updates.
                    </p>
                </div>
                <div className="flex items-center gap-2 text-xs font-medium text-neutral-500">
                    <span className={`h-2 w-2 rounded-full ${isFetching ? "bg-emerald-500 animate-pulse" : "bg-emerald-500"}`} />
                    Live · refreshes every 5s
                    {summary?.last_sent_at && <span className="hidden sm:inline">· last email {formatTime(summary.last_sent_at)}</span>}
                </div>
            </div>

            {/* Overview */}
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
                {stats.map((s) => {
                    const Icon = s.icon;
                    const active = statusFilter === s.filter && s.filter !== "";
                    return (
                        <button
                            key={s.label}
                            type="button"
                            onClick={() => { setStatusFilter(s.filter); setPage(1); }}
                            className={`group relative text-left bg-white rounded-2xl p-5 sm:p-6 border transition-all duration-300 hover:shadow-xl hover:-translate-y-1 overflow-hidden ${active ? "border-primary-300 shadow-md" : "border-neutral-100"}`}
                        >
                            <div className={`absolute top-0 left-0 right-0 h-1 bg-gradient-to-r ${s.accent} opacity-80`} />
                            <div className="flex items-start justify-between gap-2">
                                <div>
                                    <p className="text-sm font-medium text-neutral-500 mb-1">{s.label}</p>
                                    <p className="text-3xl font-display font-bold text-neutral-900 tracking-tight">
                                        {summaryLoading ? "…" : s.value ?? 0}
                                    </p>
                                </div>
                                <div className={`p-3 rounded-xl ${s.tint} transition-transform duration-300 group-hover:scale-110`}>
                                    <Icon className="w-6 h-6" />
                                </div>
                            </div>
                        </button>
                    );
                })}
            </div>

            {/* Activity */}
            <Card padding="none">
                <div className="flex flex-col md:flex-row md:items-center justify-between gap-3 p-4 sm:p-5 border-b border-neutral-100">
                    <div className="flex items-center gap-2">
                        <Mail className="w-5 h-5 text-primary-600" />
                        <h2 className="text-lg font-bold text-neutral-900">Automation activity</h2>
                    </div>
                    <div className="flex flex-col sm:flex-row gap-3">
                        <div className="inline-flex rounded-xl bg-neutral-100 p-1">
                            {STATUS_FILTERS.map((f) => (
                                <button
                                    key={f.value}
                                    type="button"
                                    onClick={() => { setStatusFilter(f.value); setPage(1); }}
                                    className={`px-3 py-1.5 text-sm font-semibold rounded-lg transition-colors ${statusFilter === f.value ? "bg-white text-neutral-900 shadow-sm" : "text-neutral-500 hover:text-neutral-800"}`}
                                >
                                    {f.label}
                                </button>
                            ))}
                        </div>
                        <div className="relative">
                            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-neutral-400" />
                            <input
                                value={searchInput}
                                onChange={(e) => setSearchInput(e.target.value)}
                                placeholder="Order #, customer or email"
                                className="w-full sm:w-64 pl-9 pr-3 py-2 text-sm rounded-xl border border-neutral-200 focus:border-primary-400 focus:ring-2 focus:ring-primary-100 outline-none"
                            />
                        </div>
                    </div>
                </div>

                <div className="overflow-x-auto">
                    <table className="w-full text-sm">
                        <thead className="bg-neutral-50 text-neutral-500 text-xs uppercase tracking-wider">
                            <tr>
                                <th className="px-5 py-3 text-left font-semibold">Order</th>
                                <th className="px-5 py-3 text-left font-semibold">Customer</th>
                                <th className="px-5 py-3 text-left font-semibold">Automation</th>
                                <th className="px-5 py-3 text-left font-semibold">Triggered event</th>
                                <th className="px-5 py-3 text-left font-semibold">Delivery</th>
                                <th className="px-5 py-3 text-left font-semibold">Timestamp</th>
                                <th className="px-5 py-3 text-right font-semibold">Actions</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-neutral-100">
                            {isLoading ? (
                                [...Array(5)].map((_, i) => <TableRowSkeleton key={i} cols={7} />)
                            ) : rows.length === 0 ? (
                                <tr>
                                    <td colSpan={7} className="px-5 py-16 text-center">
                                        <Zap className="w-10 h-10 text-neutral-300 mx-auto mb-3" />
                                        <p className="font-semibold text-neutral-700">No notifications yet</p>
                                        <p className="text-neutral-500 mt-1">
                                            They appear here automatically when customers place orders or order statuses change.
                                        </p>
                                    </td>
                                </tr>
                            ) : (
                                rows.map((n) => (
                                    <tr key={n.id} className="hover:bg-neutral-50/70 transition-colors">
                                        <td className="px-5 py-4 font-semibold text-neutral-900 whitespace-nowrap">{n.order.order_number}</td>
                                        <td className="px-5 py-4">
                                            <p className="font-medium text-neutral-900">{n.order.customer_name || "Guest"}</p>
                                            <p className="text-xs text-neutral-500">{n.recipient || n.order.customer_email || "—"}</p>
                                        </td>
                                        <td className="px-5 py-4 text-neutral-700 whitespace-nowrap">{KIND_LABELS[n.kind] ?? n.kind}</td>
                                        <td className="px-5 py-4 text-neutral-700 whitespace-nowrap">{n.event_label}</td>
                                        <td className="px-5 py-4">
                                            <DeliveryStatusBadge status={n.status} />
                                            {n.status === "failed" && n.error_message && (
                                                <p className="mt-1 max-w-[220px] truncate text-xs text-red-600" title={n.error_message}>
                                                    {n.error_message}
                                                </p>
                                            )}
                                            {n.attempts > 1 && <p className="mt-1 text-xs text-neutral-400">{n.attempts} attempts</p>}
                                        </td>
                                        <td className="px-5 py-4 text-neutral-600 whitespace-nowrap">{formatTime(n.sent_at ?? n.last_attempted_at ?? n.created_at)}</td>
                                        <td className="px-5 py-4">
                                            <div className="flex justify-end gap-1">
                                                <IconAction label="View details" onClick={() => setDetailsId(n.id)} icon={Eye} />
                                                <IconAction label="Inspect order" onClick={() => setInspectOrderId(n.order.id)} icon={ShoppingBag} />
                                                <IconAction
                                                    label={n.retryable ? "Retry delivery" : "Only failed notifications can be retried"}
                                                    onClick={() => handleRetry(n.id)}
                                                    icon={RotateCcw}
                                                    disabled={!n.retryable || retryMutation.isPending}
                                                    tone="danger"
                                                />
                                            </div>
                                        </td>
                                    </tr>
                                ))
                            )}
                        </tbody>
                    </table>
                </div>

                {meta && meta.total_pages > 1 && (
                    <div className="flex items-center justify-between px-5 py-3 border-t border-neutral-100 text-sm text-neutral-600">
                        <span>
                            Page {meta.current_page} of {meta.total_pages} · {meta.total_count} notifications
                        </span>
                        <div className="flex gap-2">
                            <button disabled={page <= 1} onClick={() => setPage((p) => p - 1)} className="px-3 py-1.5 rounded-lg border border-neutral-200 disabled:opacity-40 hover:bg-neutral-50">Previous</button>
                            <button disabled={page >= meta.total_pages} onClick={() => setPage((p) => p + 1)} className="px-3 py-1.5 rounded-lg border border-neutral-200 disabled:opacity-40 hover:bg-neutral-50">Next</button>
                        </div>
                    </div>
                )}
            </Card>

            <Modal isOpen={detailsId !== null} onClose={() => setDetailsId(null)} title="Notification details" size="xl">
                {detailsId !== null && (
                    <NotificationDetails
                        id={detailsId}
                        onRetry={handleRetry}
                        isRetrying={retryMutation.isPending}
                        onInspectOrder={(orderId) => { setDetailsId(null); setInspectOrderId(orderId); }}
                    />
                )}
            </Modal>

            <OrderInspector orderId={inspectOrderId} onClose={() => setInspectOrderId(null)} />
        </div>
    );
}

function IconAction({
    label, onClick, icon: Icon, disabled, tone = "default",
}: { label: string; onClick: () => void; icon: typeof Eye; disabled?: boolean; tone?: "default" | "danger" }) {
    return (
        <button
            type="button"
            title={label}
            aria-label={label}
            onClick={onClick}
            disabled={disabled}
            className={`p-2 rounded-lg transition-colors disabled:opacity-30 disabled:cursor-not-allowed ${
                tone === "danger" ? "text-red-600 hover:bg-red-50" : "text-neutral-600 hover:bg-neutral-100 hover:text-neutral-900"
            }`}
        >
            <Icon className="w-4 h-4" />
        </button>
    );
}

/** Opens the existing admin order modal (status changes trigger new notifications). */
function OrderInspector({ orderId, onClose }: { orderId: number | null; onClose: () => void }) {
    const { data, isLoading } = useOrder(orderId ?? 0);
    const updateMutation = useUpdateOrder();
    const order = data?.data as Order | undefined;

    const update = async (payload: { status?: string; payment_status?: string }, success: string) => {
        if (!orderId) return;
        try {
            await updateMutation.mutateAsync({ id: orderId, payload });
            toast.success(success);
        } catch (error: any) {
            toast.error(error?.message || "Update failed");
        }
    };

    return (
        <Modal isOpen={orderId !== null} onClose={onClose} title={order ? `Order Details: ${order.order_number}` : "Order details"} size="lg">
            {isLoading || !order ? (
                <div className="py-16 text-center text-sm text-neutral-500">Loading order…</div>
            ) : (
                <OrderDetailsModal
                    order={order}
                    isLoading={updateMutation.isPending}
                    onUpdateStatus={(status) => update({ status }, `Order ${status}. Customer notification queued.`)}
                    onUpdatePayment={(payment_status) => update({ payment_status }, `Payment marked as ${payment_status}`)}
                />
            )}
        </Modal>
    );
}
