<cfcomponent>
	
	<!--- 
	Richard Meredith-Hardy 21 Oct 2020	
	
	xero api docs:  https://developer.xero.com/documentation/api/api-overview
	xero oauth2 flow: https://developer.xero.com/documentation/oauth2/auth-flow#connections 
	user setup & config in xero: https://developer.xero.com/myapps 
	
	Having used a modified version of the xero-supplied oAuth 1.1 cfml library in my private xero apps for years, xero are discontinuing this type of access in mar 2021.
	In the absence of any libraries I could find which implement oAuth2 with xero in cfml, this is my effort at making one.
	
	Super credit to Matt Gifford for his oauth2 library https://github.com/coldfumonkeh/oauth2 with my added xero.cfc provider. 
	I've found oAuth2 is actually much simpler to implement than 1.1 was because it doesn't need complicated things like locally saved ssl certificates for each different private app.
	Instead, auth is tied to a user and that auth is universal across different 'tenants' in xero. So long as a tenant is already set up to do stuff in the manual first stage of doAuth() then access to
	its data is as simple as just supplying requestData() with the appropriate tenantName.
	
	Note that no code for removing connections or revoking tokens is included here because I don't need them, but they could easily be added.
	
	If you want to use this cfc, it WILL NOT work out of the box because it is designed to integrate with my existing apps as seamlessly as possible
	and it references some functions not included here eg 
	- application.org.getPerm() and application.org.setPerm() which are my way of getting and setting static settings
	- application.log.cflog2() which is my way of logging things
	But you should be able to change these easily enough for your purposes.
	
	It also talks to xero in XML by default because my apps started talking to xero at a time when their api wasn't offering json across the board 
	so even though xml is often more tricky it is my default so I don't have to rewrite a raft of functions in my apps. 
	 
	To get json data, just change the sAccept default value to "application/json" and to post or put json, change the contentType default value to "application/json"
	- beware of xero's horrible date format in a get which looks like this in raw json : "\/Date(1601884339123)\/"  or "\/Date(1453224792477+0000)\/" 
	  my solution is fixJsonDates() but it is quite heavy handed because it does a search and replace in the whole of the original incoming raw json string - but it works for me....
	 	
	Apologies for some odd or quirky things like inconsistencies in convention of variable naming eg sResourceEndpoint and tenantName or the way the name of a pdf is
	passed on, but this is how it panned out in my apps and I can't be arsed to refactor them.  I'm sure you can make it much more beautiful.
	
	enjoy.
	 --->
	 
<cffunction name="init" access="public" output="false" returntype="xero2" hint="Initializes the component">	
	<cfset this.config = application.org.getPerm('.xero2.config',"2")>
	<!---remember to re-initialize this cfc if .xero2.config changes!--->
	<cfset this.sPathToFiles = expandpath('/files/invoices')>
	<cfset this.pathToSettings = expandpath("/cfc/settings")>
	<cfset this.xero2auth = new cfc.oauth2.xero( 
									client_id = this.config.client_id,
									client_secret = this.config.client_secret,
									redirect_uri = this.config.redirect_uri)>
	<cfreturn this>
</cffunction>

<!--- this is where it all happens - build a request from the arguments and then talk to xero --->
<cffunction name="requestData" access="public" returntype="struct">
	<cfargument name="sResourceEndpoint" required="true" type="string" default="" hint="endpoint plus extra param(s) which make up the rest of the url before any ?queryString">
	<cfargument name="tenantName" required="true" type="string" default="#this.config.defaultTenant#">
	<cfargument name="stParameters" required="false" type="struct" default="#structnew()#" hint="a struct of extra params which will be added to the url as a queryString after a ? ">
	<cfargument name="sAccept" required="false" type="string" default="application/xml" hint="format which should be returned - application/xml, application/json or application/pdf">
	<cfargument name="sMethod" required="false" type="string" default="GET" hint="GET, POST or PUT as required">
	<cfargument name="sBody" required="false" type="string" default="" hint="json or xml data to send in a POST or PUT">
	<cfargument name="contentType" required="false" type="string" default="application/xml" hint="sending format in a POST or PUT, either application/json or application/xml">
	<cfargument name="ifModifiedSince" required="false" type="string" default="" hint="used in some GET queries, should be a parseable date-time in local time">
	
	<cfset var endpoint = "#this.config.xeroDataUrl#/#arguments.sResourceEndpoint#">
	<cfset var retval = {}>
	<cfset var response = "">
	<cfset var filename = "">

	<cfif this.doAuth().success eq 0>
		<cfset retval["err"] = "auth failure, see logs">
		<cfreturn retval>
	</cfif>

	<cfif structcount(arguments.stParameters)>
		<cfset endpoint = "#endpoint#?#this.encodeUrlParameters(arguments.stParameters)#">
	</cfif>

	<cfif isDate(arguments.ifModifiedSince)>
		<cfset arguments.ifModifiedSince = gethttptimestring(dateconvert('local2UTC',arguments.ifModifiedSince))>
	<cfelse>
		<cfset arguments.ifModifiedSince = "">
	</cfif>
			
	<cfset application.log.cflog2(file="dev",type="Info",text="xero2 1",obj={"arguments":arguments})>
			
	<cflock name="xero" timeout="10">
		<cfif ucase(arguments.sMethod) eq "GET" and arguments.sAccept eq "application/pdf">
			<!---this is a file download--->
			<cfhttp url="#endpoint#" method= "#arguments.sMethod#" result="response">
				<cfhttpparam type="header" name="accept" value="#arguments.sAccept#">
				<cfhttpparam type="header" name="Authorization" value="Bearer #this.getTokens().access_token#" >
				<cfhttpparam type="header" name="xero-tenant-id" value="#this.getTenantId(arguments.tenantName)#" >
			</cfhttp>
			<cfif response.status_code eq 200>
				<cfset filename = createGuid()>
				<cffile action="write" file="#this.sPathToFiles#\#filename#.pdf" output="#response.Filecontent#">
				<cfset response["Filecontent"] = fileName>
			</cfif>
		<cfelse>
			<!---all other cases eg application/xml or application/json--->
			<cfhttp url="#endpoint#" method= "#arguments.sMethod#" result="response" >
				<cfhttpparam type="header" name="Authorization" value="Bearer #this.getTokens().access_token#" >
				<cfhttpparam type="header" name="xero-tenant-id" value="#this.getTenantId(arguments.tenantName)#" >
				<cfhttpparam type="header" name="accept" value="#arguments.sAccept#">
				<cfif len(arguments.ifModifiedSince)>
					<cfhttpparam type="header" name="If-Modified-Since" value="#arguments.ifModifiedSince#">
				</cfif>
				<!--- GET has no body --->
				<cfif  listfind("POST,PUT",ucase(arguments.sMethod)) AND len(arguments.sBody)>
					<cfhttpparam type="header" name="Content-Type" value="#arguments.contentType#">
					<cfhttpparam type="body" value="#trim(arguments.sBody)#">
				</cfif>
			</cfhttp>
		</cfif>
	</cflock>

	<!---note there is an attempt to fill responseInfo.data_status further below, but data_err and actions are never filled here but are for use in enclosing functions, eg response was OK but no records returned --->
	<cfset retval["responseInfo"] = {"endpoint":endpoint,"http_status_code":response.status_code,"http_status_text":response.status_text,"http_err":"","data_status":"0","data_err":"","actions":[],"providerName":"","tenantName":arguments.tenantName,"arguments":arguments}>
	<cfif response.status_code neq "200">
		<!--- in this case filecontent should be a string containing the error message...--->
		<cfset retval["responseInfo"]["http_err"] = response.Filecontent>
		<!---write error to log--->
		<cfset application.log.cflog2(file="Xero2",type="Error",text="Xero2 responded with #response.status_code#",obj={"arguments":arguments,"retval":retval,"cfhttp_response":response})>
	</cfif>
	
	<cfset application.log.cflog2(file="dev",type="Info",text="xero2 2",obj={"arguments":arguments,"retval":retval,"response":response})>
	
	<cfif isdefined("retval.response.status")>
		<cfset retval["responseInfo"]["data_status"] = retval.response.status>
	</cfif>
	<cfif isdefined("retval.response.providerName")>
		<cfset retval["responseInfo"]["providerName"] = retval.response.providername>
	</cfif>
	
	<cfif isXML(response.Filecontent)>
		<cfset retval.response = ConvertXmlToStruct(response.Filecontent,structNew())>
	<cfelseif isJson(response.Filecontent)>
		<cfset retval.response = deserializeJson(this.fixJsonDates(response.Filecontent))>
	<cfelse>
		<cfset retval.response = response.Filecontent>
	</cfif>
	
	<cfreturn retval>
</cffunction>

<cffunction name="doAuth" access="public" returntype="struct" hint="handles all auth requests" >
	<!---relies on form values to handle next action (url & form vars are merged in lucee admin)--->
	<cfset var responseCheckString = "dfsdf89JNoljjhjh23232gj56kli6jhgsvsuioqwre">
	<cfset var result = {"content":"","success":false}>
	<cfset var tokens = {}>
	<cfset var req = getHTTPRequestData()>
	<cfset var retval = {"actions":["starting doAuth"],"success":true}>
	<cfparam name="form.state" default="when used, this should = responseCheckString">
	<cfparam name="form.code" default="" >
	
	<cftry>
		<cfif form.a eq "startXero2Auth">
			<!---we are coming in from a button to do, or re-do the first stage of the manual auth procedure. 
			note form.a was initialized elsewhere in my apps and needs a cfparam to work elsewhere --->
			<cfset var strURL = this.xero2auth.buildRedirectToAuthURL(state=responseCheckString,scope=this.config.scopes)>
			<cfset arrayappend(retval.actions,"xero2.startXero2Auth run")>
			<cfset application.log.cflog2(file="dev",type="Info",text="startXero2Auth",obj={"strURL":strURL,"form":form,"req":req,"retval":retval})>
			<!---go to xero auth page --->
			<cflocation url="#strURL#" addtoken="false">
			<cfreturn {}>
			
		<cfelseif len(trim(form.code)) and trim(form.state) eq responseCheckString>
			<!---we are coming back from xero at the redirect_uri with an authorization code and now need to get an access token --->
			<cfset arrayappend(retval.actions,"starting xero2.makeAccessTokenRequest")>
			<cfset result = this.xero2auth.makeAccessTokenRequest( code = form.code ) >
			
			<cfset retval.success = result.success>
			<cfif result.success and len(trim(result.content))>
				<cfset arrayappend(retval.actions,"xero2.makeAccessTokenRequest success")>
				<cfset tokens = deserializeJson(result.content)>
				<!---xero returns a tokens.expires_in (in seconds) value, create a tokens.expires_at value which is the true expiry time (less 30 sec to be safe)--->
				<cfset tokens["expires_at"] = dateadd("s",tokens.expires_in - 30,now())>
				<cfset this.savetokens(tokens)>
				<!---tenants might have changed, so reload--->
				<cfset this.retrieveTenants()>
			<cfelse>
				<cfset application.log.cflog2(file="xero2",type="Fatal",text="Failed to get get Access Token from code",obj={"result":result,"form":form,"tokens":this.getTokens(),"req":req,"retval":retval})>
			</cfif>
	
			<cfset application.log.cflog2(file="dev",type="Info",text="get Access Token from code",obj={"result":result,"form":form,"tokens":this.getTokens(),"req":req,"retval":retval})>
		
		<cfelseif datediff("s",now(),this.getTokens().expires_at) lt 0>
			<!---the access token has expired, get a new one using the refresh token
			strategy here is not to wait for an expired access token error and then refresh, but to use our own expires_at variable which is a bit before 
			the true expiry time.  Makes the flow is a bit more seamless ?  --->
			<cfset arrayappend(retval.actions,"starting xero2.makeRefreshTokenRequest")>
			<cfset result = this.xero2auth.makeRefreshTokenRequest(refresh_token = this.getTokens().refresh_token) >
			
			<cfset retval.success = result.success>
			<cfif result.success and len(trim(result.content))>
				<cfset arrayappend(retval.actions,"xero2.makeRefreshTokenRequest success")>
				<cfset tokens = deserializeJson(result.content)>
				<cfset tokens["expires_at"] = dateadd("s",tokens.expires_in - 30,now())>
				<cfset this.savetokens(tokens)>
			<cfelse>
				<cfset application.log.cflog2(file="xero2",type="Fatal",text="failed to get new refresh token",obj={"result":result,"form":form,"tokens":this.getTokens(),"req":req,"retval":retval})>
			</cfif>
			
			<cfset application.log.cflog2(file="dev",type="Info",text="get new refresh token",obj={"result":result,"form":form,"tokens":this.getTokens(),"req":req,"retval":retval})>
		</cfif>
		<!---in normal use, so long as the access token is still valid, none of the above if options need to run--->
	
	<cfcatch>
		<cfset application.log.cflog2(file="xero2",type="fatal",text="xero2 doAuth error - action required",obj={"error":cfcatch,"request":req,"form":form,"retval":retval})>
	</cfcatch>
	</cftry>

	<cfreturn retval>
</cffunction>

<cffunction name="encodeUrlParameters" access="public" returntype="string" hint="makes parameters for the url string" >
	<cfargument name="params" required="true" type="struct" >
	<cfset var retval = "">
	<cfset var itm = "">
	<cfloop array = "#structkeyArray(arguments.params)#" index="itm" >
		<cfset retval = listappend(retval,"#itm#=#urlencodedformat(arguments.params['#itm#'])#","&")>
	</cfloop>
	<cfreturn retval>
</cffunction>

<cffunction name="getTokens" access="public" returntype="struct" hint="gets tokens from application or file" >
	<cfargument name="forceFileRead" type="boolean" default="0" hint="true to force a file read, eg after a tokens update" >
	<cfset var st = "">
	
	<cfif isdefined("application.xero2_tokens") eq 0 OR arguments.forceFileRead eq 1>
		<cflock name="xeroTokens" type="exclusive" timeout="5" >
			<cffile action="read" file="#this.pathToSettings#/xero2tokens.json" variable="st">
		</cflock>
		<cfset application.xero2_tokens = deserializeJson(trim(st))>
	</cfif>
	
	<cfreturn application.xero2_tokens>
</cffunction>

<cffunction name="saveTokens" returntype="struct" access="public" hint="saves tokens to file" >
	<cfargument name="tokens" type="struct" required="true" hint="tokens struct" >
	<cflock name="xeroTokens" type="exclusive" timeout="5" >
		<cffile action="write" file="#this.pathToSettings#/xero2tokens.json" output="#serializeJson(arguments.tokens)#">
	</cflock>
	<cfreturn this.getTokens(1)>
</cffunction>

<cffunction name="getTenants" access="public" returntype="struct" hint="gets Tenants from application or file" >
	<cfargument name="forceFileRead" type="boolean" default="0" hint="true to force a file read, eg after a Tenants update" >
	<cfset var st = "">
	
	<cfif isdefined("application.xero2_Tenants") eq 0 OR arguments.forceFileRead eq 1>
		<cflock name="xeroTenants" type="exclusive" timeout="5" >
			<cffile action="read" file="#this.pathToSettings#/xero2tenants.json" variable="st">
		</cflock>
		<cfset application.xero2_tenants = deserializeJson(trim(st))>
	</cfif>
	<!---to keep things current, force a refresh from xero if the tenants data is more than 24 hours old--->
	<cfif datediff("h",application.xero2_tenants.updated,now()) gt 24>
		<cfset this.retrieveTenants()>
		<cfset this.getTenants(1)>
	</cfif>
	
	<cfreturn application.xero2_tenants>
</cffunction>

<cffunction name="saveTenants" returntype="struct" access="public" hint="saves Tenants to file" >
	<cfargument name="tenants" type="struct" required="true" hint="Tenants array and updated date" >
	<cflock name="xeroTenants" type="exclusive" timeout="5" >
		<cffile action="write" file="#this.pathToSettings#/xero2tenants.json" output="#serializeJson(arguments.Tenants)#">
	</cflock>
	<cfreturn this.getTenants(1)>
</cffunction>

<cffunction name="retrieveTenants" access="public" returntype="struct" hint="I retrieve details of tenants active with the current access token" >
	<!---normally a call to the xero api must include the tenant_id, but this one is different because it is getting all currently authorized tenant id's --->
	<cfset var retval = {"tenants":{},"updated":""}>
	<cfset this.doAuth()>
	<cfhttp url="#this.config.xeroConnectionsUrl#" method="GET">
		<cfhttpparam type="header" name="Authorization" value="Bearer #this.getTokens().access_token#" >
		<cfhttpparam type="header" name="Content-Type" value="application/json" >
	</cfhttp>
	<cfif len(trim(cfhttp.filecontent))>
		<cfset retval.tenants = deserializeJson(trim(cfhttp.filecontent))>
		<cfset retval.updated = now()>
		<cfset this.saveTenants(retval)>
	</cfif>
	<cfreturn retval>
</cffunction>

<cffunction name="getTenantId" returntype="string" access="public" hint="give me a tenant name and I return the tenant ID" >
	<cfargument name="tenantName"  type="string" default="#this.config.defaultTenant#" hint="One of the tenantName values as saved by retrieveTenants()" >
	<cfset var itm = {}>
	<cfloop array="#this.getTenants().tenants#" index="itm" >
		<cfif lcase(trim(arguments.tenantName)) eq lcase(trim(itm.tenantName))>
			<cfreturn itm.tenantId>
			<cfbreak>
		</cfif>
	</cfloop>
	<cfreturn "">
</cffunction>

<!--- this is adapted from one in riaforge and not the one which came from xero in their oAuth 1.1 offering (which didn't always work)
It is modded to output true values where possible (see trueVal() below).
Output is consistent, but NOT the same as if you get json directly from xero.  Watch out for values which are returned as a struct if 
there is only one of them in xero, but as an array of structs if there more than one in xero.  Since this is specific to the data being 
returned it can't easily be handled here, but if an array is expected, my solution in a data processing 
function is to insert the single struct into an array containing the struct eg <cfif not isarray(val)><cfset val = [val]></cfif>
 --->
<cffunction name="ConvertXmlToStruct" access="public" returntype="struct" output="true"	hint="Parse raw XML response body into ColdFusion structs and arrays and return it.">
	<cfargument name="xmlNode" type="string" required="true" />
	<cfargument name="str" type="struct" required="true" />
	<!---Setup local variables for recurse: --->
	<cfset var i = 0 />
	<cfset var axml = arguments.xmlNode />
	<cfset var astr = arguments.str />
	<cfset var n = "" />
	<cfset var tmpContainer = "" />

	<cfset axml = XmlSearch(XmlParse(arguments.xmlNode),"/node()")>
	<cfset axml = axml[1] />
	<!--- For each children of context node: --->
	<cfloop from="1" to="#arrayLen(axml.XmlChildren)#" index="i">
		<!--- Read XML node name without namespace: --->
		<cfset n = replace(axml.XmlChildren[i].XmlName, axml.XmlChildren[i].XmlNsPrefix&":", "") />
		<!--- If key with that name exists within output struct ... --->
		<cfif structKeyExists(astr, n)>
			<!--- ... and is not an array... --->
			<cfif not isArray(astr[n])>
				<!--- ... get this item into temp variable, ... --->
				<cfset tmpContainer = astr[n] />
				<!--- ... setup array for this item beacuse we have multiple items with same name, ... --->
				<cfset astr[n] = arrayNew(1) />
				<!--- ... and reassing temp item as a first element of new array: --->
				<cfset astr[n][1] = tmpContainer />
			<cfelse>
				<!--- Item is already an array: --->
				
			</cfif>
			<cfif arrayLen(axml.XmlChildren[i].XmlChildren) gt 0>
					<!--- recurse call: get complex item: --->
					<cfset astr[n][arrayLen(astr[n])+1] = ConvertXmlToStruct(axml.XmlChildren[i], structNew()) />
			<cfelse>
					<!--- else: assign node value as last element of array: --->
					<cfset astr[n][arrayLen(astr[n])+1] = trueVal(axml.XmlChildren[i].XmlText,n) />
			</cfif>
		<cfelse>
			<!---
				This is not a struct. This may be first tag with some name.
				This may also be one and only tag with this name.
			--->
			<!---
					If context child node has child nodes (which means it will be complex type): --->
			<cfif arrayLen(axml.XmlChildren[i].XmlChildren) gt 0>
				<!--- recurse call: get complex item: --->
				<cfset astr[n] = ConvertXmlToStruct(axml.XmlChildren[i], structNew()) />
			<cfelse>
				<cfif IsStruct(aXml.XmlAttributes) AND StructCount(aXml.XmlAttributes)>
					<cfset at_list = StructKeyList(aXml.XmlAttributes)>
					<cfloop from="1" to="#listLen(at_list)#" index="atr">
						 <cfif ListgetAt(at_list,atr) CONTAINS "xmlns:">
							 <!--- remove any namespace attributes--->
							<cfset Structdelete(axml.XmlAttributes, listgetAt(at_list,atr))>
						 </cfif>
					 </cfloop>
					 <!--- if there are any atributes left, append them to the response--->
					 <cfif StructCount(axml.XmlAttributes) GT 0>
						 <cfset astr['_attributes'] = axml.XmlAttributes />
					</cfif>
				</cfif>
				<!--- else: assign node value as last element of array: --->
				<!--- if there are any attributes on this element--->
				<cfif IsStruct(aXml.XmlChildren[i].XmlAttributes) AND StructCount(aXml.XmlChildren[i].XmlAttributes) GT 0>
					<!--- assign the text --->
					<cfset astr[n] = trueVal(axml.XmlChildren[i].XmlText,n) />
						<!--- check if there are no attributes with xmlns: , we dont want namespaces to be in the response--->
					 <cfset attrib_list = StructKeylist(axml.XmlChildren[i].XmlAttributes) />
					 <cfloop from="1" to="#listLen(attrib_list)#" index="attrib">
						 <cfif ListgetAt(attrib_list,attrib) CONTAINS "xmlns:">
							 <!--- remove any namespace attributes--->
							<cfset Structdelete(axml.XmlChildren[i].XmlAttributes, listgetAt(attrib_list,attrib))>
						 </cfif>
					 </cfloop>
					 <!--- if there are any atributes left, append them to the response--->
					 <cfif StructCount(axml.XmlChildren[i].XmlAttributes) GT 0>
						 <cfset astr[n&'_attributes'] = axml.XmlChildren[i].XmlAttributes />
					</cfif>
				<cfelse>
					 <cfset astr[n] = trueVal(axml.XmlChildren[i].XmlText,n) />
				</cfif>
			</cfif>
		</cfif>
	</cfloop>
	<!--- return struct: --->
	<cfreturn astr />
</cffunction>

<cffunction name="fixJsonDates" access="public" returntype="string" hint="give me a raw json string and I convert all dates in it from the .net epoch Date(123456) format which xero produces, to iso8601 format" >
	<!--- date strings in the json this converts look like this (inc quotes) : "\/Date(1601884339123)\/"  or "\/Date(1453224792477+0000)\/"
	are replaced with iso8601 format like this: "2016-01-19T17:33:12+0000" --->
	<cfargument name="json" type="string" default="" required="true" >
	<cfif len(trim(arguments.json)) eq 0>
		<cfreturn "">
	</cfif>
	<cfset var val = "">
	<cfset var newval = "">
	<cfset var xx = refindnocase('\"\\\/Date\([0-9]+(\+0000)?\)\\\/\"',arguments.json,1,true)>
	<cfwhile condition = "#xx.pos[1]#">
		<cfset val = mid(arguments.json,xx.pos[1],xx.len[1])>
		<cfset newVal = replacenocase(val,"+0000","","all")>
		<cfset newVal = rereplacenocase(newval,"[^0-9]+","","all") / 1000>
		<cfset newval =  datetimeformat(DateAdd("s",newval,DateConvert("utc2Local", "January 1 1970 00:00")),"iso8601")>
		<cfset newval = '"#newval#"'>
		<cfset arguments.json = replace(arguments.json,val,newval,"all")>
		<cfset xx = refindnocase('\"\\\/Date\([0-9]+(\+0000)?\)\\\/\"',arguments.json,1,true)>
	</cfwhile>

	<cfreturn arguments.json>
</cffunction>

<cfscript>
function trueVal(required string xStr, any xkey = "") {
	// added rmh
	// give me a string and I return some properly typed values 
	// only exception is any key with 'phone' in it, the value is returned as a string not a number
	var tmp = "";
	
	if (!issimplevalue(arguments.xkey))	arguments.xkey = "";

	//return arguments.xStr;
	
	//if (refindnocase("\/date\([0-9]+\)\/",arguments.xStr)) {
		//detected a xero json .net date value which is a string value in the form of "/Date(123456789)/"  where the number is epoch time in ms
	//	tmp = rereplacenocase(arguments.xStr,"[^0-9]+","","all") / 1000; // removes everything but the epoch time and converts it to sec
	//	return DateAdd("s",tmp,DateConvert("utc2Local", "January 1 1970 00:00"));
	//} else 
	if (refindnocase("^.*?(\d{4})-?(\d{2})-?(\d{2})T([\d:]+).*$",arguments.xStr)) {
		// detected iso date format "2015-12-14T09:22:10.000Z" 
		try {
		return createodbcdatetime(DateConvert("utc2Local", arguments.xStr));
		}
		catch(any e) {
			//just return the string we could not convert to date
			return trim(arguments.xStr);
		}
	} else if (listfindNoCase("true,false",xstr)) {
		//convert to boolean
		return javacast("boolean",xStr);
	} else if (isnumeric(xstr) AND findNocase("phone",xkey) eq 0) {
		//is number, key doesn't contain 'phone' : convert to number
		return javacast("double",xStr);
	}
	// probably a string, return input value
	return arguments.xStr;
}
</cfscript>

</cfcomponent>