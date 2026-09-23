# frozen_string_literal: true

require "rails/generators"

module SolidusAdvancedPricing
  module Generators
    class InstallGenerator < Rails::Generators::Base
      class_option :auto_run_migrations, type: :boolean, default: false

      source_root File.expand_path("templates", __dir__)

      def copy_initializer
        template "initializer.rb", "config/initializers/solidus_advanced_pricing.rb"
      end

      def add_migrations
        run "bin/rails railties:install:migrations FROM=solidus_advanced_pricing"
      end

      def run_migrations
        run_migrations = options[:auto_run_migrations] || ask(
          "Would you like to run the migrations now? [Y/n]"
        ).in?(["", "y", "Y"])

        if run_migrations
          run "bin/rails db:migrate"
        else
          puts "Skipping bin/rails db:migrate, don't forget to run it!" # rubocop:disable Rails/Output
        end
      end
    end
  end
end
