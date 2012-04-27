var noAlert = true;
var isOpen  = false;
var timeOut = 12000;
var tID     = '';
var shown   = [ ];

$('.site_details').live('click', showSiteDetails);
$('.show_details').live('click', showFormDetails);
$('.show_selected').live('click', populateFormDetails);
$('.show_items').live('click', showItems);
$('.remove_item').live('click', removeItem);
$('.add_item').live('click', addItem);
$('.cancel_details').live('click', cancelForm);
$('.submit_details').live('click', submitFormDetails);
$('.delete_details').live('click', deleteFormDetails);
$('#cancel_user').live('click', cancelUserForm);
$('#switch_site').live('click', switchSite);
$('#site_vips').live('click', showHosts);
$(window).bind('resize',showOverlayBox);
$(document).ready(
	function () {
//		restoreOrder('#col1');
//		restoreOrder('#col2');
		if ($('a.closeEl')) $('a.closeEl').bind('click', toggleContent);
		if ($('div.itemHeader')) $('div.itemHeader').corner('cc:#fff top');
		if ($('div.groupWrapper')) $('div.groupWrapper').Sortable(
			{
				accept: 'groupItem',
				helperclass: 'sortHelper',
				activeclass : 'sortableactive',
				hoverclass : 'sortablehover',
				handle: 'div.itemHeader',
				tolerance: 'pointer',
				floats: true,
				onChange : function(ser) { },
				onStart : function() {
					$.iAutoscroller.start();
				},
				onStop : function() {
					$.iAutoscroller.stop(serialize());
				}
			}
		);
	}
);

var toggleContent = function(e)
{
	var targetContent = $('div.itemContent', this.parentNode.parentNode);
	if (targetContent.css('display') == 'none') {
		targetContent.slideDown(300);
		$(this).html('<img src="/images/btn_collapse.gif" border="0" alt="collapse" title="collapse" />');
	} else {
		targetContent.slideUp(300);
		$(this).html('<img src="/images/btn_expand.gif" border="0" alt="expand" title="expand" />');
	}
	return false;
};


/* Overlay Functions */
function clearMessage(out) {
	if (!out) out = timeOut;
	tID = setTimeout(function(){ $('#message').html('') }, out);
}

function showOverlay(overlay) {
	if (tID) clearTimeout(tID);
	if (!overlay) overlay = 'overlay';
	$('#' + overlay).css('display', 'block');
	$('#' + overlay).height($(document).height());
	$('#message').css('color','#000000');
	$('#message').css('margin-left','10px');
	$('#message').css('font-weight','bold');
	$('#message').html('Loading...Please Wait!');
}

function hideOverlay(overlay, out) {
	if (!overlay) overlay = 'overlay';
	$('#' + overlay).css('display', 'none');
	clearMessage(out);
}

function showOverlayBox(overlay) {
	//if box is not set to open then don't do anything
	if (isOpen == false) return;
	// set the properties of the overlay box, the left and top positions
	$(overlay).css({
		display: 'block',
		left: ($(window).width() - $(overlay).width())/2,
		top: 50,
		position: 'absolute'
	});
	// set the window background for the overlay. i.e the body becomes darker
	$('.background-cover').css({
		display: 'block',
		width: $(document).width(),
		height: $(document).height(),
	});
}

function doOverlayOpen(overlay) {
	overlay = '#overlay-box-' + overlay;
	//set status to open
	isOpen = true;
	showOverlayBox(overlay);
	$('.background-cover').css({opacity:0}).animate( {opacity: 0.5, backgroundColor: '#000'} );
	// dont follow the link : so return false.
	return false;
}

function doOverlayClose(overlay) {
	overlay = '#overlay-box-' + overlay;
	//set status to closed
	isOpen = false;
	$(overlay).css( 'display', 'none' );
	// now animate the background to fade out to opacity 0
	// and then hide it after the animation is complete.
	$('.background-cover').animate( {opacity:0}, 'fast', null, function() { $(this).hide(); } );
}

function doOverlaySwap(close_overlay, open_overlay) {
	// close the current overlay
	overlay = '#overlay-box-' + close_overlay;
	//set status to closed
	isOpen = false;
	$(overlay).css( 'display', 'none' );
	// open the next overlay
	overlay = '#overlay-box-' + open_overlay;
	//set status to open
	isOpen = true;
	showOverlayBox(overlay);
	return false;
}


/* Main Functions */
function showFormDetail(event, cssClass) {
	var reg    = new RegExp( 'show_(\\w+)' );
	var got    = this.id.match( reg );
	var values = selected.attr('text').split('-');
	var id     = values.shift();
	$.getJSON('/admin/' + got[1] + '/' + id, populateFormDetails);
}

function showFormDetails(event, cssClass) {
	var reg = new RegExp( 'show_(\\w+)' );
	var got = this.id.match( reg );
	$('.list_view').show();
	$.getJSON('/admin/' + got[1], populateForm);
	doOverlayOpen(got[1]);
}

function showSiteDetails(event) {
	var siteId = $('#'+this.id).closest('tr').attr('id');
	$.getJSON('/admin/site/' + siteId, populateForm);
	$('#action').html( 'Edit' );
	$('#submitType').attr('value', 'edit');
	$('.list_view').hide();
	$('.edit_view').show();
	doOverlayOpen('site');
}

function showHosts(event) {
	var country  = $('#siteCountryCode option:selected');
	$('#site_hosts').children().remove();
	$('#'+this.id+' option:selected').each(function(){
		var option = $(this)[0].cloneNode(true);
		var value  = $(option).val();
		$.getJSON('/admin/host/' + country.val() + '/' + value, populateHosts);
	});
}

function showItems(event) {
	var reg = new RegExp( '(show|close)_(\\w+_)*(\\w+)' );
	var got = this.id.match( reg );
	var ids = '_menu';
	if (got[3]) ids = got[3] + '_menu';
	if (got[2]) ids = got[2] + ids;
	$('#'+ids).toggle();
}

function addItem(event) {
	var id  = this.id.replace( 'add_', '' );
	var reg = new RegExp( '(\\w+)_(\\w+)' );
	var got = id.match( reg );
	var ids = 'items';
	if (got) ids = got[1] + '_' + got[2] + 's';
	$('#'+ids+' option:selected').each(function(){
		var option = $(this)[0].cloneNode(true);
		var value  = $(option).val();
		if (!$('#'+id+' option[value="' + value + '"]').val()) {
			$(option).appendTo('#'+id);
		}
	});
}

function removeItem(event) {
	var id  = this.id.replace( 'remove_', '' );
	$('#'+id+' option:selected').remove();
}

function switchSite(event, cssClass) {
	var selected = $('#'+this.id+' option:selected');
	if (selected.val() == '') return;
	showOverlay();
	var path     = '/monitor/index/' + selected.val();
	document.location.href = path;
}

function submitFormDetails(event) {
	var id  = this.id.replace( 'submit_', '' );
	if (id == 'site') {
		$('#site_monitor').children().each(function(){
			$(this).attr('selected', true);
		});
		$('#site_host').children().each(function(){
			$(this).attr('selected', true);
		});
	} else {
		$('#'+id+'_group').children().each(function(){
			$(this).attr('selected', true);
		});
	}
	if ($('#'+id+'Id').val()) {
		$('#'+id+'Action').attr('value', 'updated');
	} else {
		$('#'+id+'Action').attr('value', 'created');
	}
	var params = $('#'+id+'_details').serialize();
	$.ajax(
		{
			url: '/admin/details',
			type: 'post',
			dataType: 'json',
			data: params,
			timeout: 15000,
			success: updatePage,
		}
	);
}

function cancelForm(event, cssClass) {
	var id  = $(this).attr('id');
	var reg = new RegExp( 'cancel_(\\w+)' );
	var got = id.match( reg );
	if (got) {
		cancelFormDetails(got[1]);
	}
}

function cancelFormDetails(id) {
	var name   = id.charAt(0).toUpperCase() + id.substr(1,id.length);
	var option = new Option('New '+name, 0);
	$('#'+id).children().remove();
	$('#'+id).append(option);
	$('#'+id+'_id').hide();
	$('#'+id+'Id').attr('value', '');
	$('#'+id+'Name').attr('value', '');
	if (id == 'site') {
		$('#'+id+'EndPoint').attr('value', '');
		$('#'+id+'CountryCode option:contains(US)').attr('selected', true);
		$('#site_host').children().remove();
		$('#site_monitor').children().remove();
	}
	doOverlayClose(id);
}

function cancelUserForm(event, id) {
	var type = '';
	if (typeof(event) != 'object') type = event;
	$('#'+type+'id').attr('value', '');
	$('#'+type+'userName').attr('value', '');
	$('#'+type+'firstName').attr('value', '');
	$('#'+type+'lastName').attr('value', '');
	$('#'+type+'emailAddress').attr('value', '');
	$('#'+type+'createdDate').attr('value', '');
	$('#'+type+'updatedDate').attr('value', '');
	$('#'+type+'updatedBy').attr('value', '');
	$('#'+type+'effectiveStart').attr('value', '');
	$('#'+type+'effectiveEnd').attr('value', '');
	$('#'+type+'actionType').attr('value', '');
	$('#'+type+'user_group').children().remove();
	doOverlayClose('user');
}

function populateHosts(data, type) {
	if (type == 'success') type = '';
	populateMenu(data['hosts'], 'site_hosts')
}

function populateForm(data, type) {
	if (type == 'success') type = '';
	if (data['groups']) {
		populateMenu(data['groups'], 'group')
	} else if (data['applications']) {
		populateMenu(data['applications'], 'application')
	} else if (data['permissions']) {
		populateMenu(data['permissions'], 'permission')
	} else if (data['sites']) {
		populateMenu(data['sites'], 'site')
	} else if (data['hosts']) {
		populateMenu(data['hosts'], 'host')
	} else {
		type = 'site';
		$('#'+type+'Id').attr('value', data[type]['id']);
		$('#'+type+'Name').attr('value', data[type]['name']);
		$('#'+type+'CountryCode').attr('value', data[type]['countryCode']);
		$('#'+type+'EndPoint').attr('value', data[type]['endPoint']);
		$('#'+type+'CreatedDate').attr('value', data[type]['createdDate']);
		if (data[type]['monitors']) {
			populateMenu(data[type]['monitors'], 'site_monitor')
		}
		if (data[type]['hosts']) {
			populateMenu(data[type]['hosts'], 'site_host')
		}
	}
}

function populateFormDetails(data) {
	var selected = $('#'+this.id+' option:selected');
	if (selected.val() == 0) {
		$('#'+this.id+'_id').hide();
		$('#'+this.id+'Id').attr('value', '');
		$('#'+this.id+'Name').attr('value', '');
		$('#'+this.id+'EndPoint').attr('value', '');
		if (this.id == 'site') {
			$('#'+this.id+'CountryCode option:contains(US)').attr('selected', true);
			$('#site_host').children().remove();
			$('#site_monitor').children().remove();
		}
	} else {
		var values   = selected.attr('text').split('-');
		var id       = values.shift();
		var name     = values.shift();
		var endPoint = values.shift();
		var country  = values.shift();
		$('#'+this.id+'_id').show();
		$('#'+this.id+'Id').attr('value', id);
		$('#'+this.id+'Name').attr('value', name);
		$('#'+this.id+'EndPoint').attr('value', endPoint);
		if (this.id == 'site') {
			$('#'+this.id+'CountryCode option:contains('+country+')').attr('selected', true);
			$.getJSON('/admin/site/' + id, populateSiteAttrs);
		}
	}
}

function populateMenu(data, type) {
	if (!type) type = '';
	if (data) {
		for (var i = 0; i < data.length; i++) {
			var option = new Option(data[i]['label'], data[i]['id']);
			$('#'+type).append(option);
		}
	}
}

function populateSiteAttrs(data) {
	$('#site_host').children().remove();
	$('#site_monitor').children().remove();
	if (data) {
		populateMenu(data['site']['monitors'], 'site_monitor')
		populateMenu(data['site']['hosts'], 'site_host')
	}
}

function updatePage(data) {
	updateStatus(data);
	if (data['status'] != 200) return;
//	cancelUserForm();
	cancelFormDetails(data['form']);
	path  = '/admin/index';
	path += '/limit/' + ($('#limit').val() ? $('#limit').val() : '10');
	path += '/offset/' + ($('#offset').val() ? $('#offset').val() : '0');
	setTimeout(function(){ top.location.href = path }, 1200);
}

function updateStatus(data) {
	if (tID) clearTimeout(tID);
	var status_msg = $('#message');
	if (data['status'] != 200) {
		status_msg.css('color','red');
	} else {
		status_msg.css('color','green');
	}
	status_msg.html(data['message']);
	clearMessage();
}

function deleteFormDetails(event) {
	var form = this.id.replace( 'delete_', '' );
	var id   = $('#'+form+'Id').val();
	if (id) {
		$('#'+form+'Action').attr('value', 'deleted');
		var params = $('#'+form+'_details').serialize();
		$.ajax(
			{
				url: '/admin/details',
				type: 'post',
				dataType: 'json',
				data: params,
				timeout: 100,
				success: updatePage,
			}
		);
	}
}

function serialize(s) {
	var serial = $.SortSerialize(s);
	var params = serial.hash;
	params = params + '&site=' + $('#siteId').val();
	$.ajax(
		{
			url: '/monitor/preferences',
			type: 'post',
			dataType: 'json',
			data: params,
			timeout: 100,
		}
	);
};

function restoreOrderOld(col) {
	var list = $('div.groupWrapper');
	if (list == null) return;
	// make array from saved order
	var IDs = $(col).val().split('&');
	// fetch current order
	var items = 'feeds&news&others&tests'.split('&');
	// make array from current order
	var rebuild = new Array();
	for ( var v=0; v < items.length; v++) {
		rebuild[items[v]] = items[v];
	}
	for (var i = 0; i < IDs.length; i++) {
		// item id from saved order
		var itemID = IDs[i];
		if (itemID in rebuild) {
			// select item id from current order
			var item = rebuild[itemID];
			// select the item according to current order
			var child = $('div.groupWrapper').children("#" + item);
			// select the item according to the saved order
			var savedOrd = $('div.groupWrapper').children("#" + itemID);
			// remove all the items
			child.remove();
			// add the items in turn according to saved order
			// we need to filter here since the "ui-sortable"
			// class is applied to all ul elements and we
			// only want the very first!  You can modify this
			// to support multiple lists - not tested!
			$('div.groupWrapper').filter(":first").append(savedOrd);
		}
	}
}

