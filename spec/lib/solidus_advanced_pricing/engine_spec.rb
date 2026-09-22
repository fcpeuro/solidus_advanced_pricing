# frozen_string_literal: true

require "spec_helper"

RSpec.describe "solidus_admin price types menu item" do
  subject(:item) { SolidusAdmin::Config.menu_items.find { |i| i[:key].to_s == "price_types" } }

  it "is registered once" do
    expect(SolidusAdmin::Config.menu_items.count { |i| i[:key].to_s == "price_types" }).to eq(1)
  end

  it "carries an icon that exists in the admin icon set" do
    expect(SolidusAdmin::UI::Icon::Component::NAMES).to include(item[:icon])
  end

  it "resolves to the legacy price types index" do
    url_helpers = double(solidus_admin: double(price_types_path: "/admin/price_types"))
    menu_item = SolidusAdmin::MenuItem.new(**item)

    expect(menu_item.path(url_helpers)).to eq("/admin/price_types")
  end
end
