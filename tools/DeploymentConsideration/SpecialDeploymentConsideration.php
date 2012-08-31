<?php
class SpecialDeploymentConsideration extends SpecialPage {
        function __construct() {
                parent::__construct( 'DeploymentConsideration' );
        }
        function execute( $par ) {
                global $wgRequest, $wgOut, $wgParser;
                $this->setHeaders();
                $param = $wgRequest->getText('_title');
                if (isset ($_POST['_submit1'])) {$display_mode = $_POST['_submit1'];};
                if (isset ($_POST['_submit2'])) {$display_mode = $_POST['_submit2'];};
                $changes = preg_split("/[\s,;\->:\[\]]+/", $param);
                $changes = array_unique($changes);
                $data = "";
                foreach ($changes as $value) {
            	    if (!empty($value)) {
            		$sc_deployment_page = "SC Deployment:".$value;
            		//error_log("$value, $sc_deployment_page");
	                $title = Title::newFromText( "SC:".$value );
	                $title_d = Title::newFromText( $sc_deployment_page );
	                if ( is_object( $title_d ) && $title_d->exists() && $title->exists() ) {
	            	    if ($display_mode == "Get Deployments full") {
		        	$data .= "= ______ $value _____ =\n{{:SC:".$value."}}"."\n\n";
	        	    }
	            	    if ($display_mode == "Get Deployments only") {
		        	$data .= "{{:".$sc_deployment_page."}}"."\n\n";
	            	    }
	            	}
	            }
                }
		if (!empty($data)) {
                    $wgOut->addWikiText( $data );
                }
// action="$action"
$html = <<<TEMPLATE
<form method="post" onsubmit="return setAction(this)">
    <label for="_title">Insert bugs/changes:</label>
    <textarea id="_title" name="_title" value="_title" rows="15"> </textarea>
    <input id="_submit1" name="_submit1" type="submit" value="Get Deployments only">
    <input id="_submit2" name="_submit2" type="submit" value="Get Deployments full">
</form>
TEMPLATE;
#<h2>Generate dc</h2>
    $wgOut->addHTML($html);
        }
}
