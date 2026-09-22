# frozen_string_literal: true

# solidus_admin gates every request on `spree_current_user` (SolidusAdmin::
# AuthenticationAdapters::Backend#authenticate_solidus_backend_user!), unlike
# the legacy backend's CanCan-only `authorize_admin`. This dummy app has no
# solidus_auth_devise, so nothing signs a user in; stub_authorization! only
# covers the CanCan side (current_ability), not this separate auth gate.
# A real host app already has its own auth wired up -- this is test-only.
if defined?(SolidusSupport) && SolidusSupport.admin_available?
  RSpec.configure do |config|
    config.before(:each, type: :feature) do
      allow_any_instance_of(SolidusAdmin::BaseController) # standard:disable RSpec/AnyInstance
        .to receive(:spree_current_user).and_return(Spree.user_class.new)
    end
  end
end
