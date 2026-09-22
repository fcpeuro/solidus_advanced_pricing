json.call(price, :id, :variant_id, :amount, :currency, :country_iso, :role_id, :valid_from, :valid_to)
json.display_amount price.display_amount.to_s
json.price_type_code price.price_type&.code
json.price_type_name price.price_type&.name

if can?(:update, price)
  json.admin_notes price.admin_notes
end
