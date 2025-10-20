require 'csv'

module CsvImport
  class Parser
    def initialize(file_path, shop)
      @file_path = file_path
      @shop = shop
    end

    def preview(limit = 10)
      rows = []
      CSV.foreach(@file_path, headers: true, encoding: 'UTF-8').with_index do |row, idx|
        break if idx >= limit
        rows << { row: idx + 1, data: row.to_h }
      end
      rows
    rescue CSV::MalformedCSVError => e
      raise "CSV parsing error: #{e.message}"
    end

    def detect_mappings(headers)
      mappings = {}
      confidence = 0.0

      headers.each do |header|
        normalized = header.downcase.strip

        if normalized.match?(/(title|name|product)/)
          mappings[header] = 'title'
          confidence += 0.15
        elsif normalized.match?(/(desc|description)/)
          mappings[header] = 'description'
          confidence += 0.10
        elsif normalized.match?(/(price|cost|amount)/)
          mappings[header] = 'price'
          confidence += 0.15
        elsif normalized.match?(/(sku|part|pn|code)/)
          mappings[header] = 'sku'
          confidence += 0.15
        elsif normalized.match?(/(brand|manufacturer|make)/)
          mappings[header] = 'brand'
          confidence += 0.10
        elsif normalized.match?(/(stock|quantity|qty)/)
          mappings[header] = 'stock'
          confidence += 0.10
        elsif normalized.match?(/(image|img|photo|picture)/)
          mappings[header] = 'image_urls'
          confidence += 0.10
        elsif normalized.match?(/(category|cat)/)
          mappings[header] = 'category'
          confidence += 0.10
        end
      end

      { mappings: mappings, confidence: confidence.round(2) }
    end

    def get_headers
      CSV.open(@file_path, headers: true, encoding: 'UTF-8', &:readline).headers
    rescue CSV::MalformedCSVError => e
      raise "CSV parsing error: #{e.message}"
    end
  end
end
