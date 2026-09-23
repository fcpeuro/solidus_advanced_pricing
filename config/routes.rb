# frozen_string_literal: true

Spree::Core::Engine.routes.draw do
  namespace :api, defaults: {format: "json"} do
    resources :variants, only: [] do
      resources :prices, only: [:index, :show, :create, :update, :destroy]
    end

    # Not nested under a variant: a batch spans variants, which is the point of it.
    post "prices/batch", to: "price_batches#create", as: :price_batch

    # Read-only: a client building a price payload needs the codes and ids, but
    # creating a pricing dimension is an admin act, not an API one.
    resources :price_types, only: [:index]
  end

  namespace :admin do
    resources :price_types, except: [:show]
  end
end

# SolidusAdmin::ResourcesController, which our controller inherits from, only exists
# from Solidus 4.5 -- solidus_admin itself ships from 4.3. Version check rather than
# a constant check: routes are drawn before solidus_admin's autoloads are ready.
if defined?(SolidusAdmin::Engine) && Spree.solidus_gem_version >= Gem::Version.new("4.5")
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
