# frozen_string_literal: true

module Utils
  module DedicatedOrganizationWorker
    DEDICATED_QUEUE = :wallet_refresh

    def self.organization_ids
      ENV["LAGO_DEDICATED_WORKER_ORG_IDS"].to_s.split(",").map(&:strip).reject(&:empty?)
    end

    def self.enabled_for?(organization_id)
      return false if organization_id.blank?

      organization_ids.include?(organization_id.to_s)
    end

    def self.any?
      organization_ids.any?
    end
  end
end
