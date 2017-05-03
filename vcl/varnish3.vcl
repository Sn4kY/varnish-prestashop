# This is a basic VCL configuration file for varnish.  See the vcl(7)
# man page for details on VCL syntax and semantics.
#
# Default backend definition.  Set this to point to your content
# server.
#

acl purge {
    "localhost";
}

acl nocache {
    "1.2.3.4";
}
backend default { 
    .host = "127.0.0.1";
    .port = "8080";
    .connect_timeout = 10s;
    .first_byte_timeout = 300s;
    .max_connections = 2000;
}
sub vcl_pipe {
    # Note that only the first request to the backend will have
    # X-Forwarded-For set. If you use X-Forwarded-For and want to
    # have it set for all requests, make sure to have:
    # set bereq.http.connection = "close";
    # here. It is not set by default as it might break some broken web
    # applications, like IIS with NTLM authentication.
     
    set bereq.http.connection = "close";
    return (pipe);
}
sub vcl_recv {
set req.grace = 5m;
    if (client.ip ~ nocache) {
        return(pass);
    }
    
    if (req.restarts == 0) {
	    if (req.http.x-forwarded-for) {
		    #set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
		    set req.http.X-Forwarded-For = req.http.X-Forwarded-For;
	    } else {
		    set req.http.X-Forwarded-For = client.ip;
	    }
    }

#    }
    # don't cache for dev/test
    if (req.http.host ~ "dev\.*"){
        return(pass);
    }
    set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(__[a-z]+|has_js)=[^;]*", "");

    if (req.request == "PURGE") {
	    if (!client.ip ~ purge) {
		    error 405 "Not allowed.";
	    }
	    return (lookup);
    }
    if (req.request == "GET" && (req.url ~ ".*\.php?.*$")) {
	    return (pass);
    }
    # Remove extra parameters to cache static objects
    set req.url = regsub(req.url, "\.js\?.*", ".js");
    set req.url = regsub(req.url, "\.css\?.*", ".css");
    set req.url = regsub(req.url, "\.jpg\?.*", ".jpg");
    set req.url = regsub(req.url, "\.gif\?.*", ".gif");
    set req.url = regsub(req.url, "\.swf\?.*", ".swf");
    set req.url = regsub(req.url, "\.xml\?.*", ".xml");

    # Normalize the Accept-Encoding header
    if (req.http.Accept-Encoding) {
        if (req.url ~ "\.(bmp|bz2|flv|gif|gz|ico|jpeg|jpg|mp3|ogg|pdf|png|rar|rtf|swf|tgz|wav|zip)$") {
            # No point in compressing these
            remove req.http.Accept-Encoding;
        } elsif (req.http.Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } elsif (req.http.Accept-Encoding ~ "deflate" && req.http.user-agent !~ "MSIE") {
            set req.http.Accept-Encoding = "deflate";
        } else {
            # unknown algorithm
            remove req.http.Accept-Encoding;
        }
    }
    # Ignore empty cookies
    if (req.http.Cookie ~ "^\s*$") {
        remove req.http.Cookie;
    }
    # Force cache for web assets
    if (req.url ~ "\.(bmp|bz2|css|flv|gif|gz|ico|jpeg|jpg|js|mp3|ogg|pdf|png|rar|rtf|swf|tar|tgz|txt|wav|zip)$") {
	    unset req.http.Cookie;
#	    unset req.http.Accept-Encoding;
	    unset req.http.Vary;
	    return (lookup);
    }

    if (req.http.Authorization || req.http.Cookie) {
	    /* Not cacheable by default */
	    return (pass);
    }
    #we should not cache any page for Prestashop backend
    if (req.request == "GET" && (req.url ~ "^/admin")) {
	    return (pass);
    }
    #we should not cache any page for customers
    if (req.request == "GET" && (req.url ~ "^/authentication" || req.url ~ "^/my-account")) {
	    return (pass);
    }
    #we should not cache any page for customers
    if (req.request == "GET" && (req.url ~ "^/identity" || req.url ~ "^/my-account.php")) {
	    return (pass);
    }
    #we should not cache any page for sales
    if (req.request == "GET" && (req.url ~ "^/cart.php" || req.url ~ "^/order.php" || req.url ~ "/^commande" )) {
	    return (pass);
    }
    #we should not cache any page for sales
    if (req.request == "GET" && (req.url ~ "^/addresses.php" || req.url ~ "^/order-detail.php")) {
	    return (pass);
    }
    #we should not cache any page for sales
    if (req.request == "GET" && (req.url ~ "^/order-confirmation.php" || req.url ~ "^/order-return.php")) {
	    return (pass);
    }

    #do not cache lang page
    if (req.url ~ "/fr/$" || req.url ~ "/en/$") {
    	return (pass);
    }

    # Do not cache POST request
    if (req.request == "POST") {
	  return (pipe);
    }
    # default

    if (req.request != "GET" &&
	  req.request != "HEAD" &&
	  req.request != "PUT" &&
	  req.request != "POST" &&
	  req.request != "TRACE" &&
	  req.request != "OPTIONS" &&
	  req.request != "DELETE") {
	    /* Non-RFC2616 or CONNECT which is weird. */
	    return (pipe);
    }
    if (req.request != "GET" && req.request != "HEAD") {
	    /* We only deal with GET and HEAD by default */
	    return (pass);
    }
    
    return (lookup);
}
sub vcl_fetch {
    #gzip
    if (beresp.http.content-type ~ "text") {
	set beresp.do_gzip = true;
    }
    set beresp.http.X-ServerID = beresp.backend.name;
    set beresp.grace = 5m;
    if (beresp.ttl < 8h) {
	    set beresp.ttl = 8h;
    }
    set beresp.do_gzip = true;
    set beresp.do_gunzip = false;
    set beresp.do_stream = false;
    set beresp.do_esi = false;

    if (req.url ~ "\.(js|css|jpg|jpeg|png|gif|gz|tgz|bz2|tbz|mp3|ogg|swf|pdf|ico)$" && ! (req.url ~ "\.(php)") ) {
        unset beresp.http.set-cookie;
        set beresp.http.cache-control = "max-age=604800";
    }
    if (beresp.status == 503 || beresp.status == 500) {
        set beresp.http.X-Cacheable = "NO: beresp.status";
        set beresp.http.X-Cacheable-status = beresp.status;
        return (hit_for_pass);
    }
    if (beresp.status == 403 || beresp.status == 404) {
	    return (hit_for_pass);
    }
    set beresp.http.magicmarker = "1";
    set beresp.http.X-Cacheable = "YES";
    ## Default
    if (beresp.ttl <= 0s ||
	    beresp.http.Set-Cookie ||
	    beresp.http.Vary == "*") {
			  /*
			   * Mark as "Hit-For-Pass" for the next 2 minutes
			   */
			  set beresp.ttl = 120 s;
			  return (hit_for_pass);
    }
    ## Deliver the content
    return(deliver);
}
# add response header to see if document was cached
sub vcl_deliver {
   if (obj.hits > 0) {
      set resp.http.X-Cache = "HIT";
   } else {
      set resp.http.X-Cache = "MISS";
   }
}
sub vcl_hit {
    if (req.request == "PURGE") {
	   purge;
	   error 200 "Purged.";
    }
    # Default
    return (deliver);
}
sub vcl_miss {
    if (req.request == "PURGE") {
	   purge;
	   error 200 "Purged.";
    }
    # Default
    return (fetch);
}
sub vcl_error {
  if (obj.status == 750) {
	set obj.http.Location = obj.response;
	set obj.status = 301;
	return (deliver);
  }
  // Let's deliver a friendlier error page.
  // You can customize this as you wish.
  set obj.http.Content-Type = "text/html; charset=utf-8";
  synthetic {"
  <?xml version="1.0" encoding="utf-8"?>
  <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
   "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
  <html>
	    <head>
		  <title>"} + obj.status + " " + obj.response + {"</title>
		  <style type="text/css">
		  #page {width: 400px; padding: 10px; margin: 20px auto; border: 1px solid black; background-color: #FFF;}
		  p {margin-left:20px;}
		  body {background-color: #DDD; margin: auto;}
		  </style>
	    </head>
	    <body>
	    <div id="page">
	    <h1>Page Could Not Be Loaded</h1>
	    <p>We're very sorry, but the page could not be loaded properly. This should be fixed very soon, and we apologize for any inconvenience</p>
	    <hr />
	    <h4>Debug Info:</h4>
	    <pre>Status: "} + obj.status + {"
Response: "} + obj.response + {"
XID: "} + req.xid + {"</pre>
		  </div>
	    </body>
   </html>
  "};
  return(deliver);
}
