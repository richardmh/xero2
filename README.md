## References

[xero api docs](https://developer.xero.com/documentation/api/api-overview)

[xero oauth2 flow](https://developer.xero.com/documentation/oauth2/auth-flow#connections)

[user setup & config in xero](https://developer.xero.com/myapps)

Super credit to Matt Gifford for his [oauth2 library](https://github.com/coldfumonkeh/oauth2) with my added xero.cfc provider. 

## About

Having used a modified version of the xero-supplied oAuth 1.1 cfml library in my private xero apps for years, xero are discontinuing this type of access in mar 2021.
In the absence of any libraries I could find which implement oAuth2 with xero in cfml, this is my effort at making one.
	
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
	
## Some example usages to get you started:

Verify or re-verify with xero.  
In this case you would have set https://yourdomain.com/verify.cfm as the redirect_uri in your config in xero and in your local settings
```	
<a href="verify.cfm?a=startXero2Auth">Verify with Xero</a>
<cfset application.xero2 = new cfc.xero2()>
```


## Getting data 
```
<cfset tenantName = "myTenantNameInXero">

<cfset result = application.xero2.requestData(
		tenantName = tenantName,
		sMethod = "get",
		sResourceEndpoint = "Invoices/2670b9ac-eb86-4ef9-8c61-675ae535407f")>
<cfdump var="#result#" label="get one invoice by guid">
```
same thing except it gets a pdf

```
<cfset result = application.xero2.requestData(
		tenantName = tenantName,
		sMethod = "get",
		sAccept="application/pdf",
		sResourceEndpoint = "Invoices/2670b9ac-eb86-4ef9-8c61-675ae535407f")>
<cfdump var="#result#" label="get pdf of one invoice by guid">	
```

```
<cfset result = application.xero2.requestData(
		tenantName = tenantName,
		sMethod = "get",
		sResourceEndpoint = "Invoices/1387")>
<cfdump var="#result#" label="get one Invoice by invoice number">									
```											

```
<cfset result = application.xero2.requestData(
		sMethod = "get",
		tenantName = tenantName,
		sResourceEndpoint = "Invoices",	
		stParameters = {"where":'Contact.ContactID=Guid("4AA20F7B-7F53-409B-B1A7-40B1DD934A9C")'})>						
<cfdump var="#result#" label="get invoices attached to a contact">
```

```
<cfset result = application.xero2.requestData(
		sMethod = "get",
		tenantName = tenantName,
		sResourceEndpoint = "Invoices",	
		stParameters = {"where":'Contact.ContactID=Guid("4AA20F7B-7F53-409B-B1A7-40B1DD934A9C") and Type = "ACCREC" and Status != "VOIDED" and Status != "DELETED" and Status != "DRAFT"''})>						
<cfdump var="#result#" label="get sales invoices invoices attached to a contact">
```

```
<cfset result = application.xero2.requestData(
		tenantName = tenantName,
		sMethod = "get",
		sResourceEndpoint = "Invoices",	
		stParameters = {"where":'Date >= DateTime(2019, 09, 01) && Date < DateTime(2019, 11, 01)'})>
<cfdump var="#result#" label="get invoices between 2 dates">
```

```
<cfset result = application.xero2.requestData(
		tenantName = tenantName,
		sMethod = "get",
		sResourceEndpoint = "TaxRates",
		stParameters = {"where":'Status="ACTIVE" and CanApplyToRevenue=true',"order":"TaxType"}
		)>
<cfdump var="#result#" label="get a subset of taxrates">
```

	

