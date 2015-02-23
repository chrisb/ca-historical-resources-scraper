require 'rubygems'
require 'open-uri'
require 'rest-client'
require 'nokogiri'
require 'active_support/all'
require 'csv'

# set your own cookie values here
CFID       = '123'
CFTOKEN    = '123'
JSESSIONID = '123'

COMMUNITY_PLAN_AREA = CGI.escape('la jolla')

def get_results(start=0)
  search_headers = "
    Host: sandiego.cfwebtools.com
    Connection: keep-alive
    Content-Length: 230
    Cache-Control: max-age=0
    Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8
    Origin: http://sandiego.cfwebtools.com
    User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/40.0.2214.111 Safari/537.36
    Content-Type: application/x-www-form-urlencoded
    DNT: 1
    Referer: http://sandiego.cfwebtools.com/search.cfm?display=search
    Accept-Encoding: gzip, deflate
    Accept-Language: en-US,en;q=0.8
    Cookie: CFID=#{CFID}; CFTOKEN=#{CFTOKEN}; JSESSIONID=#{JSESSIONID}
  ".strip.split("\n").map(&:strip).inject({}) { |memo,line| memo[line.split(':',2).first] = line.split(':',2).last; memo }
  search_params = "address=&apn=&hrb_number=&arch_style=&property_status=&designation_type=&community_plan_area=#{COMMUNITY_PLAN_AREA}&hrbname=&architect=&builder=&org_use=&year_designated=&age=0&District=&Neighborhood=&california=&Search_Property=Search+Property"
  resp = RestClient.post "http://sandiego.cfwebtools.com/search.cfm?start=#{start}", search_params, search_headers #.merge(cookies:@cookies)
  @cookies = resp.cookies
  return resp.to_s
end

resp        = get_results(0)
num_records = resp.match(/Displaying 1 to 25 of ([0-9]+) records/)[1].to_i
pages       = (num_records/25.0).ceil

row_headers = [
  'Detail',
  'Address',
  'Year Built',
  'Architectural Style',
  'District',
  'Location',
  'NRHP Code',
  'HRB # / Dist. Contrib. #',
  'HRB Name',
  'Property Status'
]

CSV.open("./results.csv", "wb") do |csv|
  csv << row_headers
  pages.times do |page|

    rows  = []
    start = page*25
    doc   = Nokogiri::HTML get_results(start)
    res   = doc.css('tr td.results,tr td.results2')

    res.each { |column| rows << column.parent }

    rows = rows.uniq
    rows.each do |row|
      row_data          = row.css('td').to_a.map(&:content).map(&:squish).map(&:strip)
      row_data_hash     = row_headers.inject({}) { |m,i| m[i] = row_data[row_headers.index(i)]; m }
      detail_link       = "http://sandiego.cfwebtools.com/#{row.css('td').first.css('a').first['href']}"
      resp              = Nokogiri::HTML RestClient.get(detail_link)
      image_enlarge_url = resp.css('a[href^=image_enlarge]').first

      csv << row_data               # write row_data to CSV
      next unless image_enlarge_url # move on unless theres an image to dwnload

      enlarged_image_url = "http://sandiego.cfwebtools.com/#{image_enlarge_url['href']}"
      doc                = Nokogiri::HTML RestClient.get(enlarged_image_url)
      image_url          = doc.css('img[alt^=Photograph]').first['src']
      local_filename     = "#{row_data[1].parameterize}#{File.extname(image_url)}".gsub('(','-').gsub(')','')

      puts "Downloading #{local_filename} (#{image_url})"
      `curl -o "./property_images/#{local_filename}" #{image_url}`
    end

    puts "Done with page #{page+1} of #{pages}..."
  end
end
