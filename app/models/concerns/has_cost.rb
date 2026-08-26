# A booking's price (D-trip-costs), stored as integer cents per the house
# money rule and exposed as a decimal `cost` for forms. Symbols and
# thousands separators are forgiven ("$1,240.50"); anything that still
# isn't a number stores nothing rather than something wrong.
module HasCost
  extend ActiveSupport::Concern

  def cost
    cost_cents && BigDecimal(cost_cents) / 100
  end

  def cost=(value)
    text = value.to_s.gsub(/[^\d.-]/, "")
    self.cost_cents = text.blank? ? nil : (BigDecimal(text) * 100).round
  rescue ArgumentError
    self.cost_cents = nil
  end
end
