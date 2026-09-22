# frozen_string_literal: true

Spree::Core::Engine.routes.draw do
  namespace :api, defaults: {format: "json"} do
    resources :variants, only: [] do
      resources :prices, only: [:index, :show]
    end
  end

  namespace :admin do
    resources :price_types, except: [:show]
  end
end

if defined?(SolidusAdmin::Engine)
  SolidusAdmin::Engine.routes.draw do
    # admin_resources is added via `extend` on the Mapper instance solidus_admin's
    # own routes.rb draws with -- a separate `draw` call like this one gets its
    # own Mapper, so it isn't inherited and has to be required/extended again.
    require "solidus_admin/admin_resources"
    extend SolidusAdmin::AdminResources

    # :index and the batch :destroy only -- SolidusAdmin::Engine is mounted
    # before Spree::Core::Engine (see spec/dummy's routes.rb), so a wider set
    # here (e.g. :new, :edit) would shadow the legacy backend's own working
    # forms at the same /admin/price_types/... paths with a 404, since this
    # gem intentionally doesn't implement solidus_admin new/edit components
    # for price types.
    admin_resources :price_types, only: [:index, :destroy]
  end
end
