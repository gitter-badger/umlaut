# Service that searches Google Book Search to determine viewability.
# It searches by ISBN, OCLCNUM and LCCN. If all of these identifiers are 
# available it searches by all of them and then dedupes the results.
# 
# If a full view is available it returns a fulltext service response.
# If there is only a partial view or noview it presents an appropriate 
# highlighted_link. Unfortunately there is no way tell which of the noview 
# books provide a snippet view. GBS really needs a 4th 'preview' response
# 'snippet.' 
# 
# If a thumbnail_url is returned in the responses, a cover image is displayed.
# To get the size we want some manipulation of the thumbnail_url is 
# necessary. This should work even if the Amazon service is enabled. It seems
# that the GBS cover image will overwrite the Amazon one?
# 
# FIXME This version is only for light testing since it doesn't pass correct
#  headers on. To pass the headers will necessitate a larger refactoring of the 
#  Umlaut code. In do_query see a few canned responses to use instead of actually 
#  querying GBS too much. (In testing, I think it's unlikely you're going to run into Google's traffic limits, I plan on not worrying about it until I see a problem -JR ). 
class GoogleBookSearch < Service
  require 'open-uri'
  require 'zlib'
  require 'json'
  include MetadataHelper
  
  # required params
  
  # attr_reader is important for tests
  attr_reader :url, :display_name, :num_full_views 
  
  def service_types_generated
    return [ 
      ServiceTypeValue[:fulltext], 
      ServiceTypeValue[:cover_image],
      ServiceTypeValue[:highlighted_link] ]
  end
  
  def initialize(config)
    # we include a callback in the url because it is expected that there will be one.
    @url = 'http://books.google.com/books?jscmd=viewapi&callback=gbscallback&bibkeys='
    @display_name = 'Google Book Search'
    # default number of full views to show
    @num_full_views = 1
    super(config)
  end
  
  def handle(request)
    get_viewability(request)
    return request.dispatched(self, true)
  end
  
  def get_viewability(request)
    bibkeys = get_bibkeys(request.referent)
    return nil if bibkeys.nil?
    gbs_response = do_query(bibkeys, request)
    return nil if gbs_response == 'gbscallback({});'
    
    cleaned_response = clean_response(gbs_response)
    data = parse_response(cleaned_response)
    
    data = dedupe(data) if data.length > 1
    #return full views first
    full_views_shown = create_fulltext_service_response(request, data)
    
    # only if no full view is shown, add links for partial view or noview
    unless full_views_shown
      do_web_links(request, data)
    end
    
    thumbnail_url = find_thumbnail_url(data)
    if thumbnail_url
      add_cover_image(request, thumbnail_url)    
    end
  end
  
  # returns nil or escaped string of bibkeys
  # to increase the chances of good hit, we send all available bibkeys 
  # and later dedupe by id.
  # FIXME Assumes we only have one of each kind of identifier.
  def get_bibkeys(rft)
    isbn = get_identifier(:urn, "isbn", rft)
    oclcnum = get_identifier(:info, "oclcnum", rft)
    lccn = get_identifier(:info, "lccn", rft)

    
    keys = []
    keys << 'ISBN:' + isbn if isbn
    keys << 'OCLC:' + oclcnum if oclcnum
    keys << 'LCCN:' + lccn if lccn
    
    return nil if keys.empty?
    keys = CGI.escape( keys.join(',') )
    return keys
  end
  
  def do_query(bibkeys, request)
    header = build_headers(request)
    link = @url + bibkeys
    data = open(link, 'rb', header) 
    return Zlib::GzipReader.new(data).read
    
    # stupid way to 'test' but this is what we've got
    # instead of using GBS use a canned response taken from GBS
    # comment the two lines above and uncomment on of the following lines
    #one_full_view = 'gbscallback({"ISBN:1582183392":{"bib_key":"ISBN:1582183392","info_url":"http://books.google.com/books?id=bFGPoGrAXbwC\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=bFGPoGrAXbwC\x26printsec=frontcover\x26sig=kYnPnuSmFdbm5rJfxNUN0_Qa3Zk\x26source=gbs_ViewAPI","thumbnail_url":"http://bks8.books.google.com/books?id=bFGPoGrAXbwC\x26pg=PP1\x26img=1\x26zoom=5\x26sig=bBu6nZ_q8k5uKZ43RrdBOElOCiA","preview":"full"}});'
    #one_partial_view = 'gbscallback({"ISBN:9780618680009":{"bib_key":"ISBN:9780618680009","info_url":"http://books.google.com/books?id=yq1xDpicghkC\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=yq1xDpicghkC\x26printsec=frontcover\x26sig=wuZrXklCy_Duenlw3Ea0MTgIhYQ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks8.books.google.com/books?id=yq1xDpicghkC\x26pg=PP1\x26img=1\x26zoom=5\x26sig=3sezA1j1-qzTTtI5E8PTdHJDkHw","preview":"partial"}});'
    #three_duplicate_no_view = 'gbscallback({"ISBN:0393044548":{"bib_key":"ISBN:0393044548","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks3.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=32ieZbDQYbQAeCNfW-vek8SfOxc","preview":"noview"},"OCLC:2985768":{"bib_key":"OCLC:2985768","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks4.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=Z98qalA95yde4XY6VO-1ZF0tKlE","preview":"noview"},"LCCN:76030648":{"bib_key":"LCCN:76030648","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks5.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=_qfxqS7dLZ7Oi48sFIBssQUbd4E","preview":"noview"}});'
    #one_fake_full_fake_partial = 'gbscallback({"ISBN:0393044548":{"bib_key":"ISBN:0393044548","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks3.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=32ieZbDQYbQAeCNfW-vek8SfOxc","preview":"full"},"OCLC:2985768":{"bib_key":"OCLC:2985768","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks4.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=Z98qalA95yde4XY6VO-1ZF0tKlE","preview":"noview"},"LCCN:76030648":{"bib_key":"LCCN:76030648","info_url":"http://books.google.com/books?id=E4R9AQAACAAJx\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks5.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=_qfxqS7dLZ7Oi48sFIBssQUbd4E","preview":"partial"}});'
    #two_fake_full = 'gbscallback({"ISBN:0393044548":{"bib_key":"ISBN:0393044548","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks3.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=32ieZbDQYbQAeCNfW-vek8SfOxc","preview":"full"},"OCLC:2985768":{"bib_key":"OCLC:2985768","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks4.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=Z98qalA95yde4XY6VO-1ZF0tKlE","preview":"noview"},"LCCN:76030648":{"bib_key":"LCCN:76030648","info_url":"http://books.google.com/books?id=E4R9AQAACAAJx\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks5.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=_qfxqS7dLZ7Oi48sFIBssQUbd4E","preview":"full"}});'
    #one_fake_full_one_fake_noview = 'gbscallback({"ISBN:0393044548":{"bib_key":"ISBN:0393044548","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks3.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=32ieZbDQYbQAeCNfW-vek8SfOxc","preview":"full"},"OCLC:2985768":{"bib_key":"OCLC:2985768","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks4.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=Z98qalA95yde4XY6VO-1ZF0tKlE","preview":"noview"},"LCCN:76030648":{"bib_key":"LCCN:76030648","info_url":"http://books.google.com/books?id=E4R9AQAACAAJx\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks5.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=_qfxqS7dLZ7Oi48sFIBssQUbd4E","preview":"noview"}});'
    #one_fake_partial_one_fake_noview = 'gbscallback({"ISBN:0393044548":{"bib_key":"ISBN:0393044548","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks3.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=32ieZbDQYbQAeCNfW-vek8SfOxc","preview":"partial"},"OCLC:2985768":{"bib_key":"OCLC:2985768","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks4.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=Z98qalA95yde4XY6VO-1ZF0tKlE","preview":"noview"},"LCCN:76030648":{"bib_key":"LCCN:76030648","info_url":"http://books.google.com/books?id=E4R9AQAACAAJx\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks5.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=_qfxqS7dLZ7Oi48sFIBssQUbd4E","preview":"noview"}});'
    #two_no_view_one_fake_partial = 'gbscallback({"ISBN:0393044548":{"bib_key":"ISBN:0393044548","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks3.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=32ieZbDQYbQAeCNfW-vek8SfOxc","preview":"noview"},"OCLC:2985768":{"bib_key":"OCLC:2985768","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks4.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=Z98qalA95yde4XY6VO-1ZF0tKlE","preview":"noview"},"LCCN:76030648":{"bib_key":"LCCN:76030648","info_url":"http://books.google.com/books?id=E4R9AQAACAAJx\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks5.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=_qfxqS7dLZ7Oi48sFIBssQUbd4E","preview":"partial"}});'
    #two_full_one_fake_partial = 'gbscallback({"ISBN:0393044548":{"bib_key":"ISBN:0393044548","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks3.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=32ieZbDQYbQAeCNfW-vek8SfOxc","preview":"full"},"OCLC:2985768":{"bib_key":"OCLC:2985768","info_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks4.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=Z98qalA95yde4XY6VO-1ZF0tKlE","preview":"full"},"LCCN:76030648":{"bib_key":"LCCN:76030648","info_url":"http://books.google.com/books?id=E4R9AQAACAAJx\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=E4R9AQAACAAJ\x26source=gbs_ViewAPI","thumbnail_url":"http://bks5.books.google.com/books?id=E4R9AQAACAAJ\x26printsec=frontcover\x26img=1\x26zoom=5\x26sig=_qfxqS7dLZ7Oi48sFIBssQUbd4E","preview":"partial"}});'
    #one_partial_view = 'gbscallback({"ISBN:030905382X":{"bib_key":"ISBN:030905382X","info_url":"http://books.google.com/books?id=XiiYq5U1qEUC\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=XiiYq5U1qEUC\x26printsec=frontcover\x26sig=9-7ypznOwL_rECoKJLizCBpodds\x26source=gbs_ViewAPI","thumbnail_url":"http://bks7.books.google.com/books?id=XiiYq5U1qEUC\x26pg=PP1\x26img=1\x26zoom=5\x26sig=2XmDi4HEhbqply9YjIsuopFQLAk","preview":"partial"}});'
    #one_fake_noview = 'gbscallback({"ISBN:030905382X":{"bib_key":"ISBN:030905382X","info_url":"http://books.google.com/books?id=XiiYq5U1qEUC\x26source=gbs_ViewAPI","preview_url":"http://books.google.com/books?id=XiiYq5U1qEUC\x26printsec=frontcover\x26sig=9-7ypznOwL_rECoKJLizCBpodds\x26source=gbs_ViewAPI","thumbnail_url":"http://bks7.books.google.com/books?id=XiiYq5U1qEUC\x26pg=PP1\x26img=1\x26zoom=5\x26sig=2XmDi4HEhbqply9YjIsuopFQLAk","preview":"noview"}});'
  end
  
  # We try to build a good header
  # orig headers are the client's HTTP request headers, which we stored
  # in the Request object.  We use them to make a good proxy request to
  # google. 
  def build_headers(request)

    orig_env = request.http_env || {}

    header = {}

    # Bunch of headers we proxy as-is from the original client request,
    # supplying reasonable defaults. 
    
    header["User-Agent"] = orig_env['HTTP_USER_AGENT'] || 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9) Gecko/2008061015 Firefox/3.0'
    header['Accept'] = orig_env['HTTP_ACCEPT'] || 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
    header['Accept-Language'] = orig_env['HTTP_ACCEPT_LANGUAGE'] || 'en-us,en;q=0.5'
    header['Accept-Encoding'] = orig_env['HTTP_ACCEPT_ENCODING'] || ''
    header["Accept-Charset"] = orig_env['HTTP_ACCEPT_CHARSET'] || 'UTF-8,*'

    # Set referrer to be, well, an Umlaut page, like the one we are
    # currently generating would be best. That is, the resolve link. 
    
    header["Referer"] = "http://" + 
      orig_env['HTTP_HOST'] +  orig_env['REQUEST_URI']

    # Proxy X-Forwarded headers. 

    # The original Client's ip, most important and honest. Look for
    # and add on to any existing x-forwarded-for, if neccesary, as per
    # x-forwarded-for convention. 

    header['X-Forwarded-For'] =  (orig_env['HTTP_X_FORWARDED_FOR']) ?
       (orig_env['HTTP_X_FORWARDED_FOR'] + ', ' + request.client_ip_addr) :
       request.client_ip_addr
    #Theoretically the original host requested by the client in the Host HTTP request header. We're disembling a bit. 
    header['X-Forwarded-Host'] = 'books.google.com'
    # The proxy server: That is, Umlaut, us. 
    header['X-Forwarded-Server'] = orig_env['SERVER_NAME']  
    
    return header
  end
  
  # Since we have a callback as part of the response we need to remove it.
  # Also & is escaped and must be replaced.
  def clean_response(resp)
     resp = resp.sub(/^gbscallback\(/,'')
     resp = resp.sub(/\);$/,'')
     resp = resp.gsub('\x26','&')
     return resp
  end
  
  # besides parsing the JSON we flatten it to make it easier to work with.
  def parse_response(resp)
    j = JSON.parse(resp)
    a = []
    j.each do |k,v|
      a << v
    end
    return a
  end
    
  # We only create a fulltext service response if we have a full view.
  # We create only as many full views as are specified in config.
  def create_fulltext_service_response(request, data)
    display_name = @display_name
    
    full_views = data.select { |d| d['preview'] == 'full'  }
    return nil if full_views.empty?
    count = 0
    full_views.each do |fv|
      #note = fv['bib_key'].gsub(':', ': ') #get_search_title(request.referent)
      request.add_service_response(
        {:service=>self, 
          :display_text=>display_name, 
          :url=>fv['preview_url']}, 
          #:notes=>note}, 
        [ :fulltext ]) 
      count += 1
      break if count == @num_full_views
    end   
    return true
  end
  
  # create highlighted_link service response for partial and noview
  # Only show one web link. prefer a partial view over a noview
  def do_web_links(request, data)    
    # some noview items will have a snippet view, but we have no way to tell
    info_views = data.select{|d| d['preview'] == 'partial' }    
    
    if info_views.blank?
      info_views = data.select{|d| d['preview'] == 'noview'}
    end
    
    # Shouldn't ever get to this point, but just in case
    return nil if info_views.blank?
    
    url = ''
    iv = info_views.first
    if iv['preview'] == 'partial'
      url = iv['preview_url']      
      display_text = "Limited Preview"
       # FIXME just for debugging
       notes = iv['bib_key']
    else
      url = iv['info_url']
      display_text = "Book Information"
      # FIXME just for debugging
      notes = iv['bib_key']      
    end
    request.add_service_response( { 
        :service=>self,    
        :url=>url,
        :display_text=>display_text,
        :service_data => {:notes => notes}},
      [ServiceTypeValue[:highlighted_link]]    )    
  end
  
  # We don't need to present a link for every bibkey if they are duplicates.
  # We test duplicates by comparing info_urls. This ought to be safe since if
  #   gbs returns a hit it ought to at least have an info_url.
  # Right now we keep bibkey a string and just stuff in the other bibkeys.
  # FIXME could be just stoopid to keep bibkey as a string, but then again we
  #   might not need it at this stage so just discard it?
  def dedupe(data)
    kept_urls = []
    saved = []
    data.each do |d|
      if kept_urls.include? d['info_url']
        # stuff the bibkey into a matching hit
        matching_saved = saved.select { |s| s['info_url'] == d['info_url']  }[0]
        matching_saved['bib_key'] <<  ', ' << d['bib_key']
      else # move into saved and record the info_url
        kept_urls << d['info_url']
        saved << d
      end
    end
    return saved
  end
  
#  def extract_id(single_record)
#     m = (single_record['info_url']).scan(/id=(.*)&/)
#     m[0]
#  end
 
  # Not all responses have a thumbnail_url. We look for them and return the 1st.
  def find_thumbnail_url(data)
    thumbnail_urls = data.select{|d| d['thumbnail_url']}
    # pick the first of the available thumbnails
    thumbnail_urls[0]['thumbnail_url'] unless thumbnail_urls.empty?
  end
  
  # FIXME currently we run this service foreground so we can pick up cover 
  #   images. If we want this as a background service we need to make
  #   cover_image a background service.
  #   ( We just need to fix the view AJAX updater to update the cover image div 
  #   for cover image background services. This can be done. )
  def add_cover_image(request, url)
    # We do like in Amazon service and return three sizes of images. 
    # it seems only size 1 = large and 5 = small work so medium and large 
    # are the same
    [["small", '5'],["medium", '1'], ["large", '1']].each do | size, zoom_size |
      zoom_url = url.sub('zoom=5', "zoom=#{zoom_size}")
      
      # if we're sent to a page other than the frontcover then strip out the
      # page number and insert front cover
      zoom_url.sub!(/&pg=.*?&/, '&printsec=frontcover&')
      
      request.add_service_response({
          :service=>self, 
          :display_text => 'Cover Image',
          :key=> size, 
          :url => zoom_url, 
          # FIXME how is service_data used? we just put in fake data for asin
          # and repeated the size from key
          :service_data => {:asin => 'asin', :size => size }
        },
        [ServiceTypeValue[:cover_image]])
    end
  end
  
end


# Test WorldCat links
# FIXME: This produces two 'noview' links because the ids don't match.
#   This might be as good as we can do though, unless we want to only ever show
#   one 'noview' link. Notice that the metadata does differ between the two.
# http://localhost:3000/resolve?url_ver=Z39.88-2004&rfr_id=info%3Asid%2Fworldcat.org%3Aworldcat&rft_val_fmt=info%3Aofi%2Ffmt%3Akev%3Amtx%3Abook&req_dat=%3Csessionid%3E&rft_id=info%3Aoclcnum%2F34576818&rft_id=urn%3AISBN%3A9780195101386&rft_id=urn%3AISSN%3A&rft.aulast=Twain&rft.aufirst=Mark&rft.auinitm=&rft.btitle=The+prince+and+the+pauper&rft.atitle=&rft.date=1996&rft.tpages=&rft.isbn=9780195101386&rft.aucorp=&rft.place=New+York&rft.pub=Oxford+University+Press&rft.edition=&rft.series=&rft.genre=book&url_ver=Z39.88-2004
#
# Snippet view returns noview through the API
# http://localhost:3000/resolve?rft.isbn=0155374656
#