<?xml version="1.0" encoding="utf-8"?>
<!--
  Maps a decoded ADT^A01 to a small patient summary. Written for the schema generated from HL7's v2.5 v2.xml
  (root ADT_A01_25, names such as PID_5_PatientName/XPN_0_FamilyName/FN_0_Surname). Only the message root is in a
  namespace; segments, fields and components are not. Groups (ADT_A01_PROCEDURE) come from the schema.
-->
<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:ns0="http://lambogenius.com/HealthCare/HL7/2X"
                exclude-result-prefixes="ns0">
  <xsl:output method="xml" indent="yes"/>

  <xsl:template match="/ns0:ADT_A01_25">
    <xsl:variable name="born" select="PID/PID_7_DateTimeOfBirth/TS_0_Time"/>
    <xsl:variable name="bed" select="PV1/PV1_3_AssignedPatientLocation"/>
    <xsl:variable name="doctor" select="PV1/PV1_7_AttendingDoctor[1]"/>
    <PatientSummary mappedWith="schema">
      <ControlId><xsl:value-of select="MSH/MSH_10_MessageControlID"/></ControlId>
      <Event><xsl:value-of select="MSH/MSH_9_MessageType/MSG_1_TriggerEvent"/></Event>
      <MedicalRecordNumber><xsl:value-of select="PID/PID_3_PatientIdentifierList[CX_4_IdentifierTypeCode = 'MR']/CX_0_IDNumber"/></MedicalRecordNumber>
      <FamilyName><xsl:value-of select="PID/PID_5_PatientName[1]/XPN_0_FamilyName/FN_0_Surname"/></FamilyName>
      <GivenName><xsl:value-of select="PID/PID_5_PatientName[1]/XPN_1_GivenName"/></GivenName>
      <BirthDate><xsl:value-of select="concat(substring($born, 1, 4), '-', substring($born, 5, 2), '-', substring($born, 7, 2))"/></BirthDate>
      <Sex><xsl:value-of select="PID/PID_8_AdministrativeSex"/></Sex>
      <Location><xsl:value-of select="concat($bed/PL_0_PointOfCare, ' ', $bed/PL_1_Room, '-', $bed/PL_2_Bed)"/></Location>
      <AttendingDoctor><xsl:value-of select="concat($doctor/XCN_5_PrefixEGDR, ' ', $doctor/XCN_2_GivenName, ' ', $doctor/XCN_1_FamilyName/FN_0_Surname)"/></AttendingDoctor>
      <Observations>
        <xsl:for-each select="OBX">
          <Observation code="{OBX_3_ObservationIdentifier/CE_0_Identifier}" units="{OBX_6_Units/CE_0_Identifier}">
            <xsl:value-of select="OBX_5_ObservationValue"/>
          </Observation>
        </xsl:for-each>
      </Observations>
      <Procedures count="{count(ADT_A01_PROCEDURE)}">
        <xsl:for-each select="ADT_A01_PROCEDURE/PR1">
          <Procedure code="{PR1_3_ProcedureCode/CE_0_Identifier}"><xsl:value-of select="PR1_3_ProcedureCode/CE_1_Text"/></Procedure>
        </xsl:for-each>
      </Procedures>
      <!--
        ZPV is a site-defined Z segment. The schema doesn't define it, so its names are generic (ZPV_2_0), and it stays
        where it was in the message: after the last PR1, which puts it inside the last ADT_A01_PROCEDURE group.
        //ZPV finds it wherever it is.
      -->
      <Flag><xsl:value-of select="//ZPV/ZPV_2/ZPV_2_0"/></Flag>
    </PatientSummary>
  </xsl:template>
</xsl:stylesheet>
