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

  def delete_invoice(id)
    invoice = Invoice.find(id)
    puts "Retrieved invoice #{invoice.id} from organization #{invoice.organization.name}"

    puts "Deleting invoice #{invoice.id}..."
    ActiveRecord::Base.transaction do
      invoice.taxes.destroy_all
      invoice.fees.destroy_all
      invoice.destroy
    end

    begin
      invoice.reload
      puts "Invoice #{id} could not be deleted. Please try again."
    rescue ActiveRecord::RecordNotFound
      puts "Invoice #{id} has been successfully deleted."
    end
  end
end
