# frozen_string_literal: true

module Rails::ConsoleMethods
  def find(id)
    if /^gid/.match?(id)
      GlobalID::Locator.locate(id)
    elsif EmailValidator::EMAIL_REGEXP.match?(id)
      User.find_by email: id
    else
      raise "Don't know how to resolve this ¯\\_(ツ)_/¯. Please provide a valid email or Global ID."
    end
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
