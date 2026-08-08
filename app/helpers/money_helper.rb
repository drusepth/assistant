# Formatting for signed cents everywhere money renders, in the
# household's currency (D-spending-mirror: `households.currency`'s named
# consumer). Cents in, string out — no floats anywhere in money math.
module MoneyHelper
  CURRENCY_SYMBOLS = {
    "USD" => "$", "EUR" => "€", "GBP" => "£", "JPY" => "¥", "CAD" => "$",
    "AUD" => "$", "NZD" => "$", "CHF" => "CHF ", "INR" => "₹", "MXN" => "$",
    "BRL" => "R$", "ZAR" => "R", "SEK" => "kr ", "NOK" => "kr ", "DKK" => "kr ",
    "PLN" => "zł ", "KRW" => "₩", "CNY" => "¥", "PHP" => "₱", "TRY" => "₺"
  }.freeze

  ZERO_DECIMAL = %w[ JPY KRW VND ].freeze

  def money_amount(cents, signed: false)
    return "—" if cents.nil?

    code = Current.user&.household&.currency.presence || "USD"
    symbol = CURRENCY_SYMBOLS.fetch(code, "#{code} ")
    decimals = ZERO_DECIMAL.include?(code) ? 0 : 2
    magnitude = number_with_precision(cents.abs / 100.0, precision: decimals, delimiter: ",")

    prefix = if cents.negative? then "−"
    elsif signed && cents.positive? then "+"
    else ""
    end
    "#{prefix}#{symbol}#{magnitude}"
  end

  # Ledger convention: spending rows are negative cents, but a spending
  # total reads better unsigned ("$412 of $520"). This flips money-out
  # into positive display terms.
  def money_out(cents) = money_amount(cents&.abs)
end
