# frozen_string_literal: true

module SolidusAdvancedPricing
  module Spree
    module PermittedAttributesDecorator
      # `prepend`ing PermittedAttributes.singleton_class hands `prepended` the
      # singleton class itself, and mattr_accessor rejects being called on
      # one ("module attributes should be defined directly on class, not
      # singleton") -- so the accessor is defined on the module directly.
      #
      # Not a module-level constant: solidus_support `load`s this file on
      # every to_prepare, which would otherwise warn on every reload
      # ("already initialized constant").
      def self.prepended(_base)
        target = ::Spree::PermittedAttributes

        unless target.respond_to?(:price_attributes)
          target.mattr_accessor(:price_attributes) { [:amount, :currency, :country_iso] }
        end

        target.price_attributes |= [:price_type_id, :role_id, :valid_from, :valid_to, :admin_notes]
      end

      ::Spree::PermittedAttributes.singleton_class.prepend self
    end
  end
end
