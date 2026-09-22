# frozen_string_literal: true

Spree::Core::Engine.routes.draw do
  namespace :admin do
    resources :price_types, except: [:show]
  end
end
