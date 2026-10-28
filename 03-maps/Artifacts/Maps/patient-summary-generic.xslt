<?xml version="1.0" encoding="utf-8"?>
<!--
  The same patient summary, for XML decoded with no schema (allowSchemaless): fields are named PID_5, components
  PID_5_0 (0-based), sub-components PID_5_0_0, and there are no groups, so PR1 segments sit directly under the root.
  A component with no sub-components is plain text. The root is matched with /* so its name and namespace don't matter.
-->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" indent="yes"/>

  <xsl:template match="/*">
    <xsl:variable name="born" select="PID/PID_7"/>
    <xsl:variable name="bed" select="PV1/PV1_3"/>
    <xsl:variable name="doctor" select="PV1/PV1_7[1]"/>
    <PatientSummary mappedWith="generic names">
      <ControlId><xsl:value-of select="MSH/MSH_10"/></ControlId>
      <Event><xsl:value-of select="MSH/MSH_9/MSH_9_1"/></Event>
      <MedicalRecordNumber><xsl:value-of select="PID/PID_3[PID_3_4 = 'MR']/PID_3_0"/></MedicalRecordNumber>
      <FamilyName><xsl:value-of select="PID/PID_5[1]/PID_5_0"/></FamilyName>
      <GivenName><xsl:value-of select="PID/PID_5[1]/PID_5_1"/></GivenName>
      <BirthDate><xsl:value-of select="concat(substring($born, 1, 4), '-', substring($born, 5, 2), '-', substring($born, 7, 2))"/></BirthDate>
      <Sex><xsl:value-of select="PID/PID_8"/></Sex>
      <Location><xsl:value-of select="concat($bed/PV1_3_0, ' ', $bed/PV1_3_1, '-', $bed/PV1_3_2)"/></Location>
      <AttendingDoctor><xsl:value-of select="concat($doctor/PV1_7_5, ' ', $doctor/PV1_7_2, ' ', $doctor/PV1_7_1)"/></AttendingDoctor>
      <Observations>
        <xsl:for-each select="OBX">
          <Observation code="{OBX_3/OBX_3_0}" units="{OBX_6/OBX_6_0}">
            <xsl:value-of select="OBX_5"/>
          </Observation>
        </xsl:for-each>
      </Observations>
      <Procedures count="{count(PR1)}">
        <xsl:for-each select="PR1">
          <Procedure code="{PR1_3/PR1_3_0}"><xsl:value-of select="PR1_3/PR1_3_1"/></Procedure>
        </xsl:for-each>
      </Procedures>
      <Flag><xsl:value-of select="//ZPV/ZPV_2/ZPV_2_0"/></Flag>
    </PatientSummary>
  </xsl:template>
</xsl:stylesheet>
