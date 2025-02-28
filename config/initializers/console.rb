# frozen_string_literal: true

module Rails::ConsoleMethods
  if Rails.env.development?
    def gavin
      @gavin ||= hooli.users.find_by email: "gavin@hooli.com"
    end

    def hooli
      @hooli ||= Organization.find_by name: "Hooli"
    end

    def delete_hooli_webhooks
      hooli.webhook_endpoints.map do |endpoint|
        endpoint.webhooks.delete_all
      end.sum
    end
  end

  def find(id)
    if /^gid/.match?(id)
      GlobalID::Locator.locate(id)
    elsif EmailValidator::EMAIL_REGEXP.match?(id)
      User.find_by email: id
    else
      raise "Don't know how to resolve this ¯\\_(ツ)_/¯. Please provide a valid email or Global ID."
    end
  end

  def enable_premium_integration!(org_id, integration_name)
    org = Organization.find(org_id)
    org.premium_integrations << integration_name
    org.save!
    org.reload.premium_integrations
  end

  def enable_all_premium_integrations!(org_id)
    org = Organization.find(org_id)
    org.update! premium_integrations: Organization::PREMIUM_INTEGRATIONS
    org.reload.premium_integrations
  end

  def hard_delete_invoice(id)
    invoice = Invoice.find(id)
    puts "Going to hard delete invoice from org `#{invoice.organization.name}` (id: #{invoice.id})" # rubocop:disable Rails/Output

    puts "Press any key to confirm deletion or CTRL+C to cancel." # rubocop:disable Rails/Output
    c = $stdin.getch

    if c == "\u0003"
      puts "Deletion cancelled." # rubocop:disable Rails/Output
      return invoice
    end

    puts "Deleting invoice #{invoice.id}..." # rubocop:disable Rails/Output
    ActiveRecord::Base.transaction do
      invoice.invoice_subscriptions.destroy_all
      invoice.credit_notes.destroy_all
      invoice.fees.each { |f| f.true_up_fee&.destroy! }
      invoice.fees.destroy_all
      invoice.taxes.destroy_all
      invoice.credits.destroy_all
      invoice.applied_invoice_custom_sections.destroy_all
      invoice.destroy!
    end

    begin
      invoice.reload
      puts "Invoice #{id} could not be deleted. Please try again." # rubocop:disable Rails/Output
    rescue ActiveRecord::RecordNotFound
      puts "Invoice #{id} has been successfully deleted." # rubocop:disable Rails/Output
    end
  end
end
