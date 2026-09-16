# frozen_string_literal: true

FactoryBot.define do
  factory :price_type, class: 'SolidusAdvancedPricing::PriceType' do
    sequence(:name) { |n| "Price Type #{n}" }
    sequence(:code) { |n| "price_type_#{n}" }
    position { 100 }
    default { false }
  end
end
