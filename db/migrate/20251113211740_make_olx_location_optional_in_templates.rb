class MakeOlxLocationOptionalInTemplates < ActiveRecord::Migration[8.0]
  def change
    # Make olx_location_id nullable since OLX.ba uses GPS coordinates instead of city IDs
    change_column_null :olx_category_templates, :olx_location_id, true
  end
end
