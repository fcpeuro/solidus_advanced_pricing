# frozen_string_literal: true

module SolidusAdmin
  module PriceTypes
    module Index
      # Read-only listing. Create/edit/destroy for SolidusAdvancedPricing::PriceType
      # stay on the legacy backend (spree.*_admin_price_type_path) -- mirrors how
      # adjustment_reasons' index links back to the legacy backend rather than a
      # new-admin form.
      class Component < ::SolidusAdmin::UI::Pages::Index::Component
        def model_class = ::SolidusAdvancedPricing::PriceType

        def search_key = :name_or_code_cont

        def search_url = solidus_admin.price_types_path

        def edit_path(price_type)
          spree.edit_admin_price_type_path(price_type, **search_filter_params)
        end

        def page_actions
          render component("ui/button").new(
            tag: :a,
            text: t(".add"),
            href: spree.new_admin_price_type_path,
            icon: "add-line",
            class: "align-self-end w-full"
          )
        end

        def batch_actions
          [
            {
              label: t(".batch_actions.delete"),
              action: solidus_admin.price_types_path(**search_filter_params),
              method: :delete,
              icon: "delete-bin-7-line"
            }
          ]
        end

        def columns
          [
            {
              header: :name,
              data: ->(price_type) do
                link_to price_type.name, edit_path(price_type), class: "body-link"
              end
            },
            {
              header: :code,
              data: ->(price_type) do
                link_to price_type.code, edit_path(price_type), class: "body-link"
              end
            },
            {
              header: :position,
              data: ->(price_type) { price_type.position }
            },
            {
              header: :role_id,
              data: ->(price_type) { price_type.role&.name || t("solidus_advanced_pricing.all_customers") }
            }
          ]
        end
      end
    end
  end
end
