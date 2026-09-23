# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spree::Variant, "#price_of_type and #base_price" do
  let(:variant) { create(:variant, price: 100) }
  let(:now) { Time.zone.parse("2026-06-15 12:00:00") }
  let(:sale_type) { SolidusAdvancedPricing::PriceType.find_by(code: "sale") }
  let(:wholesale_type) { SolidusAdvancedPricing::PriceType.find_by(code: "wholesale") }

  def options(**overrides)
    SolidusAdvancedPricing::PricingOptions.new(
      {currency: "USD", country_iso: nil, at: now, customer_role_ids: []}.merge(overrides)
    )
  end

  describe "#base_price" do
    it "returns the untyped price when a cheaper sale-typed price also exists" do
      create(:price, variant: variant, amount: 70, price_type: sale_type)
      variant.reload
      expect(variant.base_price(options).amount).to eq(100)
    end

    it "returns nil when the variant has no untyped price" do
      variant.prices.each(&:destroy)
      create(:price, variant: variant, amount: 70, price_type: sale_type)
      variant.reload
      expect(variant.base_price(options)).to be_nil
    end
  end

  describe "#price_of_type" do
    it "returns the sale price when given a code" do
      create(:price, variant: variant, amount: 70, price_type: sale_type)
      variant.reload
      expect(variant.price_of_type("sale", options).amount).to eq(70)
    end

    it "accepts a PriceType record" do
      create(:price, variant: variant, amount: 70, price_type: sale_type)
      variant.reload
      expect(variant.price_of_type(sale_type, options).amount).to eq(70)
    end

    it "accepts a price type id" do
      create(:price, variant: variant, amount: 70, price_type: sale_type)
      variant.reload
      expect(variant.price_of_type(sale_type.id, options).amount).to eq(70)
    end

    it "raises ArgumentError for an unresolvable code" do
      expect { variant.price_of_type(:not_a_real_code, options) }.to raise_error(ArgumentError)
    end

    it "returns nil when the type has no price for this variant" do
      variant.reload
      expect(variant.price_of_type(wholesale_type, options)).to be_nil
    end

    it "honors validity windows: an expired sale-typed price is not returned" do
      create(:price, variant: variant, amount: 70, price_type: sale_type, valid_from: now - 5.days, valid_to: now - 1.day)
      variant.reload
      expect(variant.price_of_type(sale_type, options)).to be_nil
    end

    describe "customer context" do
      let(:wholesale_role) { create(:role, name: "wholesale") }

      before do
        create(:price, variant: variant, amount: 60, price_type: sale_type, role: wholesale_role)
        variant.reload
      end

      it "returns the role-targeted price for a customer holding the role" do
        result = variant.price_of_type(sale_type, options(customer_role_ids: [wholesale_role.id]))
        expect(result&.amount).to eq(60)
      end

      it "does not return the role-targeted price for a guest" do
        result = variant.price_of_type(sale_type, options(customer_role_ids: []))
        expect(result).to be_nil
      end
    end
  end
end
