# frozen_string_literal: true

# `unchanged` is a model whose count, or a lambda whose value, a refused call must leave as it was.
RSpec.shared_examples "refused on a shadow organization" do |unchanged|
  define_method(:unchanged_state) { unchanged.is_a?(Proc) ? instance_exec(&unchanged) : unchanged.count }

  %w[shadowing paused].each do |status|
    context "when the organization is the shadow of a #{status} migration" do
      before { create(:billing_engine_migration, organization: create(:organization), shadow_organization: organization, status:) }

      it "refuses with shadow_organization_outbound_disabled" do
        expect { subject }.not_to change { unchanged_state }

        expect(subject).to be_failure
        expect(subject.error).to be_a(BaseService::ForbiddenFailure)
        expect(subject.error.code).to eq("shadow_organization_outbound_disabled")
      end
    end
  end

  context "when the organization is the shadow of an aborted migration" do
    before { create(:billing_engine_migration, organization: create(:organization), shadow_organization: organization, status: "aborted") }

    it { expect(subject).to be_success }
  end

  context "when the organization is the source of a migration" do
    before { create(:billing_engine_migration, organization:) }

    it { expect(subject).to be_success }
  end
end
