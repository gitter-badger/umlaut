# Uses ISI Web of Knowledge to generates links to "cited by" and "similar"
# articles.
#
# REQUIREMENTS: You must be an ISI customer if you want these links to actually
# work for your users. Off-campus users should be sent through EZProxy, see
# the EZProxy plug-in.
# 
# You need to register for the  the Thomson 'Links Article Match Retrieval'
# (LAMR) service api, which is used here. To register, see:
# http://isiwebofknowledge.com/products_tools/products/related/trlinks/.
#
# You register by IP address, so no API key is needed once your registration
# goes through. 
#
# If you later need to change the IP addresses entitled to use this API, use
# http://scientific.thomson.com/scientific/techsupport/cpe/form.html.
# to request a change. 
class Isi < Service
  require  'open-uri'
  require 'json'
  require 'hpricot'
  require 'net/http'
  
  include MetadataHelper
  
  
  def service_types_generated
    return [ServiceTypeValue[:cited_by]]
  end

  def initialize(config)
    #defaults
    @wos_app_name = "Umlaut"
    @display_name = "ISI Web of Knowledge"
    @api_url = "https://ws.isiknowledge.com/esti/xrpc"
    @include_cited_by = true
    @include_similar = true
    super(config)
  end

  def handle(request)
    
    unless ( sufficient_metadata?(request.referent))
       return request.dispatched(self, true)
    end
    
    xml = gen_lamr_request(request)
    
    isi_response = do_lamr_request(xml)
    
    add_responses( request, isi_response )
    
    return request.dispatched(self, true)
  end

  # A DOI is always sufficient. Otherwise, it gets complicated because the ISI
  # service is kind of picky in weird ways. ISSN alone is not enough, we need
  # jtitle.  Once you have jtitle, Vol/issue/start page are often enough, but
  # article title really helps, and jtitle+atitle+year is often enough too. 
  def sufficient_metadata?(referent)
    metadata = referent.metadata
    return get_doi(referent) ||
        (  ( metadata['jtitle'] || 
             metadata['title'] )   &&           
           (! (metadata['atitle'].blank? ||
              metadata['date'].blank?
              ) ||
            ! ( metadata['volume'].blank? || metadata['issue'].blank? ||
                metadata['spage'].blank?))
        )    
  end

  # produces XML to be posted to Thomson 'Links Article Match Retrieval' service api. 
  def gen_lamr_request(request)
    output = ""
    
    builder = Builder::XmlMarkup.new(:target => output, :indent => 2)
    builder.instruct!(:xml, :encoding => "UTF-8")    

    builder.request(:xmlns => "http://www.isinet.com/xrpc41", :src => "app.id=Umlaut") do
      builder.fn(:name => "LinksAMR.retrieve") do
        builder.list do
          # first map is authentication info. empty 'map' element since we are IP authenticated. 
          builder.map
          # specify what we're requesting
          builder.map do
            builder.list(:name=>"WOS") do
              builder.val("timesCited")
              builder.val("ut")
              builder.val("doi")
              builder.val("sourceURL")
              builder.val("citingArticlesURL")
              builder.val("relatedRecordsURL")
            end
          end
          # specify our query
          builder.map do
            builder.map(:name => "cite_id") do
              # Here's the tricky part, depends on what we've got.
              metadata = request.referent.metadata

              # DOI
              if ( doi = get_doi(request.referent))
                builder.val(doi, :name => "doi")
              end

              # Journal title is crucial for ISI -- ISSN alone is
              # not enough, weirdly! 
              if ( ! metadata['jtitle'].blank? )
                builder.val(metadata['jtitle'], :name => "stitle" )
              else
                builder.val(metadata['title'], :name => 'stitle' )
              end
              
              # ISSN, not actually used much by ISI, but can't hurt. 
              if ( issn = request.referent.issn )
                # ISSN _needs_ a hyphen for WoS, bah!
                unless issn.match( /\-/ )
                  issn = issn[0,4] + '-' + issn[4,7]
                end
                builder.val(issn, :name => "issn")
              end

              # article title often helpful. 
              unless ( metadata['atitle'].blank?)
                builder.val( metadata['atitle'], :name => "atitle")
              end
              # year
              unless ( metadata['date'].blank?)
                #first four digits are year
                builder.val( metadata["date"][0,4], :name => "year" )
              end

              # Vol/issue/page.  Oddly, issue isn't used very strongly
              # by ISI, but can't hurt. 
              unless ( metadata['volume'].blank? )
                builder.val(metadata['volume'], :name => 'vol')
              end
              unless ( metadata['issue'].blank? )
                builder.val( metadata['issue'] , :name => 'issue')
              end
              unless ( metadata['spage'].blank? )
                builder.val(metadata['spage'], :name => 'spage ')
              end
              
            end
          end          
        end
      end
    end
    return output
  end

  def do_lamr_request(xml)
    uri = URI.parse(@api_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if (uri.scheme == 'https')

    headers = {'Content-Type' => 'application/xml'}
    
    return http.post(uri.request_uri, xml, headers)
  end

  def add_responses(request, isi_response)
    hpricot = Hpricot.XML(isi_response.body)

    # Check for errors.
    if (error = (hpricot.at('val[@name = "error"]') || hpricot.at('null[@name = "error"]')))
      raise Exception.new("ISI service reported error: #{error.inner_text}")
    end
    
    results = hpricot.at('map[@name ="cite_id"] map[@name="WOS"]')

    # cited by
    
    count = results.at('val[@name="timesCited"]')
    count = count ? count.inner_text.to_i : 0    
    
    cited_by_url = results.at('val[@name="citingArticlesURL"]')
    cited_by_url = cited_by_url.inner_text if cited_by_url

    if (@include_cited_by && count > 0 && cited_by_url )
      request.add_service_response(:service=>self, 
        :display_text => "#{count} #{ServiceTypeValue[:cited_by].display_name_pluralize.downcase.capitalize}", 
        :count=> count, 
        :url => cited_by_url, 
        :service_type_value => :cited_by)
    end
    
    # similar
    
    similar_url = results.at('val[@name ="relatedRecordsURL"]')
    similar_url = similar_url.inner_text if similar_url

    if (@include_similar && similar_url )
        request.add_service_response( :service=>self, 
          :display_text => " #{ServiceTypeValue[:similar].display_name_pluralize.downcase.capitalize}", 
          :url => similar_url, 
          :service_type_value => :similar)
    end
    
  end
  
end