class Order < ApplicationRecord
  belongs_to :organization, foreign_key: :org_id
  belongs_to :user
  has_many :order_items, dependent: :destroy
  has_many :payments, dependent: :destroy
  has_many :status_events, -> { order(:created_at, :id) }, class_name: "OrderStatusEvent", inverse_of: :order, dependent: :destroy
  has_many :notification_deliveries, dependent: :destroy

  STATUSES = %w[pending confirmed shipped delivered cancelled].freeze
  PAYMENT_STATUSES = %w[unpaid paid refunded].freeze

  # Server-side pricing rules (mirrors what the checkout page displays).
  TAX_RATE = BigDecimal("0.18")
  FREE_SHIPPING_THRESHOLD = BigDecimal("999")
  STANDARD_SHIPPING_FEE = BigDecimal("50")

  # Shared placeholder account used for guest checkout (see OrdersController#guest_checkout_user).
  GUEST_EMAIL_PATTERN = /\Aguest-orders\+.*@example\.local\z/

  validates :order_number, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }
  validates :total, numericality: { greater_than_or_equal_to: 0 }
  validates :customer_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, on: :create

  before_validation :set_defaults, on: :create
  before_validation :generate_order_number, on: :create
  before_validation :calculate_totals, on: :create

  def self.shipping_fee_for(subtotal)
    subtotal > FREE_SHIPPING_THRESHOLD ? BigDecimal("0") : STANDARD_SHIPPING_FEE
  end

  def guest?
    user&.email_address.to_s.match?(GUEST_EMAIL_PATTERN)
  end

  # Where customer notifications go: the checkout email, else the account email.
  def notification_email
    customer_email.presence || (user&.email_address unless guest?)
  end

  def shipping_address_hash
    JSON.parse(shipping_address.presence || "{}")
  rescue JSON::ParserError
    {}
  end

  private

  def set_defaults
    self.status ||= "pending"
    self.payment_status ||= "unpaid"
  end

  def generate_order_number
    self.order_number ||= "ORD-#{Time.current.to_i}-#{SecureRandom.hex(3).upcase}"
  end

  # Totals are computed once, on the server, from the persisted variant prices.
  # Client-supplied tax / shipping_fee values are ignored.
  def calculate_totals
    items = order_items.reject(&:marked_for_destruction?)
    self.subtotal = items.sum { |item| item.price.to_d * item.quantity.to_i }
    self.shipping_fee = self.class.shipping_fee_for(subtotal)
    self.tax = (subtotal * TAX_RATE).round(2)
    self.total = (subtotal + tax + shipping_fee).round(2)
  end
end
