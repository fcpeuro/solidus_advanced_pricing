json.price_types(@price_types) do |price_type|
  json.partial!("spree/api/price_types/price_type", price_type: price_type)
end
