param (
	$Username,
	$Password,
	$OperationType = "Full"
)

# CONFIG **********************************************************************

$FailSafe = 700  # Throw an error if the number of returned users is less then this

$XML = "feideData.xml"

$ADDomain = "mgk.no"
$ADPathGroups  = "OU=[FIM] Grupper,OU=MGK,DC=mgk,DC=no"

$ADPathEmployees = "OU=[FIM] Ansatte,OU=MGK,DC=mgk,DC=no"
$ADPathDisabledEmployees = "OU=Deaktivert,OU=[FIM] Ansatte,OU=MGK,DC=mgk,DC=no"

$ADPathStudents  = "OU=[FIM] Elever,OU=MGK,DC=mgk,DC=no"   
$ADPathDisabledStudents  = "OU=Deaktivert,OU=[FIM] Elever,OU=MGK,DC=mgk,DC=no"  


$ADLDSDomain = "@midtre-gauldal.kommune.no"
$ADLDSPathEmployees = "CN=People,DC=midtre-gauldal,DC=kommune,DC=no"
$ADLDSPathStudents  = "CN=People,DC=midtre-gauldal,DC=kommune,DC=no"
$ADLDSPathOrganizations  = "CN=Organization,DC=midtre-gauldal,DC=kommune,DC=no" #Trap

$Log = "log.txt"

$OrgNr = "NO970187715"
$OrgName = "S�r-Tr�ndelag"
$OrgMail = "postmottak@midtre-gauldal.kommune.no"
$OrgTlf = "72403000"
$OrgAddress = "R�dhuset"
$norEduOrgSchemaVersion = "1.5.1" 	# https://www.feide.no/sites/feide.no/files/documents/go_attributter.pdf

#**************************************************************************
# ABOUT: Version: 0.6, Author: kimberg88@gmail.com

Set-Location $(split-path -parent $MyInvocation.MyCommand.Definition) # Set working directory to script directory


$Groups = @{}
$global:ReturnedUsers = 0

Function AddToGroup($GroupName, $MemberSSN) {
    If($Groups.Count -gt 0) { # Pretty, pretty Lame
        If($Groups.Get_Item($GroupName)) {
            if(-not $Groups.Get_Item($GroupName).Contains($SSN)) {
                $Members = $Groups.Get_Item($GroupName) + $SSN
                $Groups.Set_Item($GroupName, $Members)
            }
        } else { 
            $Groups.Add($GroupName, @($SSN))
        }
    } else {
        $Groups.Add($GroupName, @($SSN))
    }
}

try {
    $Culture = (Get-Culture).TextInfo
	[xml]$PersonXML =  Get-Content $XML
    "$(Get-Date) :: Import Start" | Out-File $Log -Append
 

    "$(Get-Date) :: Process Group Relations" | Out-File $Log -Append
    Foreach ($Relation in $PersonXML.document.relation) {
        if($Relation.subject.groupid.groupidtype -eq "kl-ID") { 
            $GroupName = $Relation.subject.groupid.'#text' # ST�RU:9A
            $SSN = $Relation.object.personid[0].'#text'        
            
            AddToGroup $GroupName $SSN
        }

        if ($Relation.subject.org) {
            $UserType = $Relation.relationtype
            $UnitName = $Relation.subject.org.ouid.'#text'  # ST�RU

            switch ($UserType) { 
                "has-pupil"   { $GroupName_All = $UnitName + "_ALLE-ELEVER" }
                "has-teacher" { $GroupName_All = $UnitName + "_ALLE-LAERERE" }
                "has-staff"   { $GroupName_All = $UnitName + "_ALLE-ANSATTE" }
            }

            Foreach ($P in $Relation.object.personid) {
                if ($P.personidtype -eq "Fnr") {
                    $SSN = $P.'#text'
                    AddToGroup ($UnitName + "_ALLE") $SSN
                    AddToGroup $GroupName_All $SSN
                }
            }
        }
		
		
    }
	
	
	"$(Get-Date) :: Project Main Organization" | Out-File $Log -Append
    $obj = @{}
    $obj.add("SATS_OrgNr", $OrgNr)
	$obj.add("objectClass", "organization")
    $obj.add("SATS_OrgName", $OrgName)
    $obj.add("SATS_OrgMail", $OrgMail ) 
    $obj.add("SATS_telephone", $OrgTlf ) 
    $obj.add("SATS_postalAddress", $OrgAddress) 
	$obj.add("SATS_norEduOrgSchemaVersion", $norEduOrgSchemaVersion) 
    $obj.add("SATS_ADLDSPath", $ADLDSPathOrganizations)
    $obj.add("SATS_ADLDSDomain", $ADLDSDomain)
    $obj


    Foreach ($Group in $Groups.GetEnumerator()) {
        $GroupName = $Group.key
        $GroupName = "FIM-SATS." + $GroupName.Replace("/", " ").Replace("\", " ").Replace(":","_") # Trim unwanted characters
       "$(Get-Date) :: Project Group: $($GroupName)" | Out-File $Log -Append

        if ($GroupName.Length -gt 60) { # Max CN limit in Active Directory is 64
            $GroupName = $GroupName.Substring(0,60) 
        }
            
        $obj = @{}
        $obj.add("SATS_name", $GroupName)
		$obj.add("objectClass", "group")
        $obj.add("SATS_ADPath", $ADPathGroups)
        $obj.add("Member", $Group.Value) 
        $obj
    } 

    Foreach ($Unit in $PersonXML.document.organization.ou) {
        $UnitOrgNR = "NO" + $Unit.ouid[1].'#text'
		$UnitName = $Unit.ouname[0].'#text'
        "$(Get-Date) :: Project Unit: $UnitOrgNR" | Out-File $Log -Append

        $obj = @{}
        $obj.add("SATS_UnitOrgNr", $UnitOrgNR)
	    $obj.add("objectClass", "unit")
        $obj.add("SATS_OrgName", $UnitName)
        $obj.add("SATS_OrgMail", $OrgMail) #$Unit.contactinfo[2].'#text'
        $obj.add("SATS_telephone", $Unit.contactinfo[0].'#text') 
        $obj.add("SATS_MemberOfOrganization", $OrgNr) 
        $obj.add("SATS_ADLDSPath", $ADLDSPathOrganizations)
        $obj.add("SATS_ADLDSDomain", $ADLDSDomain)
        $obj
		$obj | Out-File $Log -Append
    }
	
	Foreach ($Person in $PersonXML.document.person) {
        $SSN = $Person.personid[0].'#text'
        "$(Get-Date) :: Project Person: $SSN " | Out-File $Log -Append

        $MemberOfGroups = $Groups.GetEnumerator() | Where-Object { $_.Value.Contains($SSN) }
        if($MemberOfGroups | Where-Object { $_.Name.contains('ELEVER') } ) {
            $Type = "student"
            $ADPath = $ADPathStudents
            $ADLDSPath = $ADLDSPathStudents
			$ADLDSPathDisabled = $ADPathDisabledStudents
			$Trinn = $MemberOfGroups | Where-Object { $_.Name -Match "[0-9]" }
			$Trinn = $Trinn.Name -creplace "[^0-9]"
			$Department = $Trinn + " trinn"
			# https://www.feide.no/sites/feide.no/files/go_attributter_1.6-jul2015.pdf
			$Entitlement = "urn:mace:feide.no:go:grep:http://psi.udir.no/laereplan/aarstrinn/aarstrinn$($Trinn)"
        } else {
			$Department = $NULL
			$Entitlement = $NULL
            $Type = "employee"
            $ADPath = $ADPathEmployees
            $ADLDSPath = $ADLDSPathEmployees
			$ADLDSPathDisabled = $ADPathDisabledEmployees
        }
		
		Foreach ($Unit in $PersonXML.document.organization.ou) {
			$UnitOrgNR = "NO" + $Unit.ouid[1].'#text'
			$UnitName = $Unit.ouid[2].'#text'
			if ($MemberOfGroups | Where-Object { $_.Name.contains($UnitName) }) {
				$MemberOfUnit = $UnitOrgNR
				$MemberOfUnitName = $UnitName
			}
		}

        $obj = @{}
		$obj.add("SATS_ssn", $SSN)
		$obj.add("objectClass", "user")
        $obj.add("SATS_Fullname", $Person.name.fn)
        $obj.add("SATS_Firstname", $Person.name.n.given)
        $obj.add("SATS_Lastname", $Person.name.n.family)
        $obj.add("SATS_Status", "Active")
        $obj.add("SATS_Comment", "FIM-SATS : $($MemberOfUnitName) : $($Type)")
        $obj.add("SATS_Type", $Type)
		$obj.add("SATS_Department", $Department)
		$obj.add("SATS_Affilliation", ("member", $Type))
		$obj.add("SATS_Entitlement", $Entitlement)
        $obj.add("SATS_ADPath", $ADPath)
		$obj.add("SATS_ADPathDisabled", $ADLDSPathDisabled)
        $obj.add("SATS_ADLDSPath", $ADLDSPath)
        $obj.add("SATS_ADDomain", $ADDomain)
        $obj.add("SATS_ADLDSDomain", $ADLDSDomain)
		$obj.add("SATS_MemberOfOrganization", $OrgNr) 
		$obj.add("SATS_MemberOfUnit", $MemberOfUnit) 
        $obj
		$global:ReturnedUsers++
    }


	
	if ($ReturnedUsers -lt $FailSafe) {
		$Error = "The script returned less users then the specified failsafe-threshold. Something likely went wrong... Threshold: $($FailSafe). Returned users: $($ReturnedUsers)"
		#Throw $Error
		$Error | Out-File $Log -Append
	}
	
	"$(Get-Date) :: Import End" | Out-File $Log -Append
} catch {
    $_ | Out-File $Log -Append
}

