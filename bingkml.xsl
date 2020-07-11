<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:kml="http://www.opengis.net/kml/2.2">
<xsl:output method="xml" indent="yes" encoding="UTF-8"
  cdata-section-elements="kml:description"/>

<xsl:template match="kml:Document">
  <xsl:copy>
    <xsl:apply-templates select="kml:Style"/>
    <xsl:apply-templates select="kml:Placemark"/>
  </xsl:copy>
</xsl:template>

<xsl:template match="@*|node()">
  <xsl:copy>
    <xsl:apply-templates select="@*|node()"/>
  </xsl:copy>
</xsl:template>

</xsl:stylesheet>
