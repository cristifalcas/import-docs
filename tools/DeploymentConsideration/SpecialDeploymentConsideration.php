<?php
class SpecialDeploymentConsideration extends SpecialPage {
        function __construct() {
                parent::__construct( 'DeploymentConsideration' );
        }
 
        function execute( $par ) {
                global $wgRequest, $wgOut;
                $this->setHeaders();
 
                $param = $wgRequest->getText('_title');
                $changes = preg_split("/[\s,;\->:]+/", $param);
                $changes = array_unique($changes);
                $data = "";
                foreach ($changes as $value) {
            	    if (!empty($value)) {
            		$sc_deployment_page = "SC Deployment:".$value;
	                $titleObject = Title::newFromText( $sc_deployment_page );
	                if ( $titleObject->exists() ) {
	            	    $data .= "{{:".$sc_deployment_page."}}"."\n\n";
	            	}
	            }
                }
		if (!empty($data)) {
                    $wgOut->addWikiText( $data );
                }

$html = <<<TEMPLATE
<form method="post" action="$action" onsubmit="return setAction(this)">
    <label for="_title">Insert bugs/changes:</label>
    <textarea id="_title" name="_title" value="_title" rows="15"> </textarea>
    <input type="submit" value="Send">
</form>
TEMPLATE;
#<h2>Generate dc</h2>
    $wgOut->addHTML($html);

        }
}
