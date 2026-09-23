# frozen_string_literal: true

require "spec_helper"

# A feature spec visiting spree.admin_stores_path can't exercise this: in the
# dummy app SolidusAdmin::Engine is mounted at /admin ahead of
# Spree::Core::Engine and owns the Stores controller outright, so the legacy
# _configuration_menu partial (only ever rendered from stores#index/#edit/#new
# in solidus_backend) is never reached by any live route. Rendering the
# partial directly is the only way to give the Deface override real coverage
# in this app.
RSpec.describe "spree/admin/shared/_configuration_menu", type: :view do
  before do
    view.class.include Spree::Admin::NavigationHelper
    view.class.include Spree::BaseHelper
    view.class.include Rails.application.routes.url_helpers
    view.class.include Spree::Core::Engine.routes.url_helpers
  end

  it "links to the price types index when the admin can manage price types" do
    allow(view).to receive(:can?).and_return(true)

    render partial: "spree/admin/shared/configuration_menu"

    expect(view.content_for(:tabs)).to have_link(
      "Price Types", href: Spree::Core::Engine.routes.url_helpers.admin_price_types_path
    )
  end

  it "hides the link when the admin cannot manage price types" do
    allow(view).to receive(:can?) { |_action, subject| subject != SolidusAdvancedPricing::PriceType }

    render partial: "spree/admin/shared/configuration_menu"

    expect(view.content_for(:tabs)).not_to have_link("Price Types")
  end
end
