module OrderMailerHelper
  def inr(amount)
    "₹#{format('%.2f', amount.to_d)}"
  end

  def address_lines(address)
    [
      address["full_name"],
      address["address"],
      [address["city"], address["state"], address["zip_code"]].compact_blank.join(", "),
      address["phone"],
    ].compact_blank
  end
end
