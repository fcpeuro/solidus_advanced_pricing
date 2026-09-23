json.prices(@prices) do |price|
  json.partial!("spree/api/prices/price", price: price)
end
