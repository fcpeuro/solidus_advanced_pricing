# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidusAdvancedPricing::PricingOptions do
  describe "defaults" do
    subject(:options) { described_class.new }

    it "pins the price type to nil, meaning untyped base prices only" do
      expect(options.desired_attributes[:price_type_id]).to be_nil
    end

    it "pins role_id to nil so the admin sees the untargeted price" do
      expect(options.desired_attributes).to have_key(:role_id)
      expect(options.desired_attributes[:role_id]).to be_nil
    end

    it "treats a caller with no user as a guest" do
      expect(options.customer_role_ids).to eq([])
    end

    it "defaults the evaluation time to now" do
      freeze_time do
        expect(options.at).to eq(Time.current)
      end
    end
  end

  it "keeps at and customer_role_ids out of desired_attributes" do
    options = described_class.new(at: Time.current, customer_role_ids: [1])
    expect(options.desired_attributes).not_to have_key(:at)
    expect(options.desired_attributes).not_to have_key(:customer_role_ids)
  end

  it "does not mutate the hash it is given" do
    attributes = {at: Time.current, customer_role_ids: [1]}
    described_class.new(attributes)
    expect(attributes).to have_key(:at)
  end

  it "can be built for a price" do
    price = create(:price)
    options = described_class.from_price(price)
    expect(options.desired_attributes[:price_type_id]).to eq(price.price_type_id)
  end

  describe ".from_context" do
    let(:store) { create(:store) }
    let(:context) { double(current_spree_user: user, current_store: store) }

    context "with a guest" do
      let(:user) { nil }

      it "has no customer roles" do
        expect(described_class.from_context(context).customer_role_ids).to eq([])
      end
    end

    context "with a customer holding a pricing-relevant role" do
      let(:role) { create(:role, name: "wholesale") }
      let(:user) { create(:user, spree_roles: [role]) }

      before { create(:price, role: role) }

      it "carries that role" do
        expect(described_class.from_context(context).customer_role_ids).to eq([role.id])
      end
    end

    it "narrows away roles no price references" do
      irrelevant = create(:role, name: "newsletter")
      user = create(:user, spree_roles: [irrelevant])
      expect(described_class.from_context(double(current_spree_user: user, current_store: store)).customer_role_ids)
        .to eq([])
    end

    it "clears the pinned price type so every type competes" do
      expect(described_class.from_context(double(current_spree_user: nil, current_store: store))
        .desired_attributes[:price_type_id]).to eq(:any)
    end
  end

  it "keeps Spree::Price.with_default_attributes valid" do
    expect { ::Spree::Price.with_default_attributes.to_a }.not_to raise_error
  end
end
