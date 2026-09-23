# frozen_string_literal: true

require "bundler/gem_tasks"
require "solidus_dev_support/rake_tasks"
SolidusDevSupport::RakeTasks.install

task default: "extension:specs"

# The stock dummy app template (spree/testing_support, as of solidus_dev_support
# 2.12) predates solidus_admin and neither mounts its engine nor builds its
# assets, so a freshly generated dummy app 404s on every admin page. Both fixes
# below only apply when solidus_admin is actually a dependency of this gem.
if Rake::Task.task_defined?("extension:test_app") && Gem.loaded_specs.key?("solidus_admin")
  Rake::Task["extension:test_app"].enhance do
    dummy_root = File.expand_path("spec/dummy", __dir__)

    # solidus_admin ships a precompiled tailwind.css in the released gem, but the
    # git-source checkout used in dev/CI omits it (built only by `rake release`).
    # Without it, Sprockets raises FileNotFound for any admin page. A stub is
    # sufficient here since these specs don't assert on styling.
    tailwind_css = File.join(dummy_root, "app/assets/builds/solidus_admin/tailwind.css")
    unless File.exist?(tailwind_css)
      require "fileutils"
      FileUtils.mkdir_p(File.dirname(tailwind_css))
      FileUtils.touch(tailwind_css)
    end

    # Per the solidus_admin README, SolidusAdmin::Engine must be mounted *before*
    # Spree::Core::Engine so its routes take precedence over the legacy backend's
    # for any resource both admins define (otherwise Spree::Core::Engine, mounted
    # at '/', claims every request first and solidus_admin is never reached).
    routes_path = File.join(dummy_root, "config/routes.rb")
    routes = File.read(routes_path)
    unless routes.include?("SolidusAdmin::Engine")
      File.write(routes_path, routes.sub(
        "Rails.application.routes.draw do",
        "Rails.application.routes.draw do\n  mount SolidusAdmin::Engine, at: '/admin' if defined?(SolidusAdmin::Engine)"
      ))
    end
  end
end
