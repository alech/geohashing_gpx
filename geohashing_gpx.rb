require 'rubygems'
require 'sinatra'
require 'json'
require 'open-uri'
require 'haml'

# MAX number of additional geohashes in each direction
MAX_COUNT = 3

def waypoint(lat, lon, name)
	%Q|<wpt lat="#{lat}" lon="#{lon}">\n  <name>#{name}</name>\n</wpt>\n|
end

def relet_json(lat, lon, date)
	json_data = open "http://relet.net/geo/#{lat}/#{lon}/#{date}"  do |f|
		f.read
	end
	JSON.load(json_data)
end

def gpx_header
	<<"XEOF"
<?xml version="1.0" encoding="UTF-8"?>
<gpx
  version="1.0"
  creator="http://geohashing-gpx.heroku.com"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns="http://www.topografix.com/GPX/1/0"
  xsi:schemaLocation="http://www.topografix.com/GPX/1/0 http://www.topografix.com/GPX/1/0/gpx.xsd">
XEOF
end

def gpx_footer
	"</gpx>"
end

def gpx(lat, lon, count, date, today = false)
	result = gpx_header
	dates = [ date ]
	if today && (lon > -30) &&
	   ((Time.now.utc.hour == 13 && Time.now.min >= 30) ||
	   (Time.now.utc.hour > 13)) then
		# if 30W rule applies and it is after 13:30 UTC,
		# also get next day's geohash
		dates << (Time.now.utc + 60*60*24).strftime("%Y-%m-%d")
	end
	dates.each do |date|
		(lat-count..lat+count).each do |curr_lat|
			(lon-count..lon+count).each do |curr_lon|
				j = relet_json(curr_lat, curr_lon, date)
				next if j['error'] # ignore errors
				result << waypoint(j['lat'], j['lon'], "#{curr_lat},#{curr_lon} at #{date}")
			end
		end
		j = relet_json(lat, lon, date)
		if j['global-lat'] then
			result << waypoint(j['global-lat'], j['global-lon'], "Globalhash at #{date}")
		end
	end
	result << gpx_footer
	result
end

configure do
	mime_type :gpx, 'text/xml'
end

# routes
get %r|\A/single/(-?\d{1,2})/(-?\d{1,2})\z| do |lat, lon|
	today = Time.now.utc.strftime("%Y-%m-%d")
	content_type :gpx
	gpx(lat.to_i, lon.to_i, 0, today, true)
end

get %r|\A/single/(-?\d{1,2})/(-?\d{1,2})/(\d{4}-\d{2}-\d{2})\z| do |lat, lon, date|
	content_type :gpx
	gpx(lat.to_i, lon.to_i, 0, date)
end

get %r|\A/multi/(\d)/(-?\d{1,2})/(-?\d{1,2})\z| do |count, lat, lon|
	count = count.to_i
	today = Time.now.utc.strftime("%Y-%m-%d")
	if count <= MAX_COUNT then
		content_type :gpx
		gpx(lat.to_i, lon.to_i, count, today, true)
	else
		halt 403, 'too many multi points requested'
	end
end

get %r|\A/multi/(\d)/(-?\d{1,2})/(-?\d{1,2})/(\d{4}-\d{2}-\d{2})\z| do |count, lat, lon, date|
	count = count.to_i
	if count <= MAX_COUNT then
		content_type :gpx
		gpx(lat.to_i, lon.to_i, count, date)
	else
		halt 403, 'too many multi points requested'
	end
end

get %r|\A/stops/(-?\d{1,2})/(-?\d{1,2})/(\d{4}-\d{2}-\d{2})\z| do |lat, lon, date|
	j = relet_json(lat, lon, date)
	hp_lat = j['lat'].to_f
	hp_lon = j['lon'].to_f
	look_x = ("%2.6f" % [ hp_lon ]).sub('.', '')
	look_y = ("%2.6f" % [ hp_lat ]).sub('.', '')
	redirect "http://m.bahn.de/bin/mobil/query2.exe/dox?performLocating=2&tpl=stopsnear&look_maxdist=5000&look_x=#{look_x}&look_y=#{look_y}"
end

get '/' do
	haml :index
end
