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
