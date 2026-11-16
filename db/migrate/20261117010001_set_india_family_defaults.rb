class SetIndiaFamilyDefaults < ActiveRecord::Migration[7.2]
  def change
    change_column_default :families, :currency, from: "USD", to: "INR"
    change_column_default :families, :country, from: "US", to: "IN"
    change_column_default :families, :date_format, from: "%m-%d-%Y", to: "%d-%m-%Y"
    change_column_default :families, :timezone, from: nil, to: "Asia/Kolkata"
  end
end
