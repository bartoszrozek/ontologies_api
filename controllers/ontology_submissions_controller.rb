class OntologySubmissionsController < ApplicationController
  get "/submissions" do
    check_last_modified_collection(LinkedData::Models::OntologySubmission)
    #using appplication_helper method
    options = {include_views: params["include_views"], status: (params["include_status"] || "ANY")}
    reply retrieve_latest_submissions(options).values
  end

  ##
  # Create a new submission for an existing ontology
  post "/submissions" do
    ont = Ontology.find(uri_as_needed(params["ontology"])).include(Ontology.goo_attrs_to_load).first
    error 422, "You must provide a valid `acronym` to create a new submission" if ont.nil?
    reply 201, create_submission(ont)
  end

  namespace "/ontologies/:acronym/submissions" do

    ##
    # Display all submissions of an ontology
    get do
      ont = Ontology.find(params["acronym"]).include(:acronym).first
      error 422, "Ontology #{params["acronym"]} does not exist" unless ont
      check_last_modified_segment(LinkedData::Models::OntologySubmission, [ont.acronym])
      ont.bring(submissions: OntologySubmission.goo_attrs_to_load(includes_param))
      reply ont.submissions.sort {|a,b| b.submissionId <=> a.submissionId }  # descending order of submissionId
    end

    ##
    # Create a new submission for an existing ontology
    post do
      ont = Ontology.find(params["acronym"]).include(Ontology.attributes).first
      error 422, "You must provide a valid `acronym` to create a new submission" if ont.nil?
      reply 201, create_submission(ont)
    end

    ##
    # Display a submission
    get '/:ontology_submission_id' do
      ont = Ontology.find(params["acronym"]).include(:acronym).first
      check_last_modified_segment(LinkedData::Models::OntologySubmission, [ont.acronym])
      ont.bring(:submissions)
      ont_submission = ont.submission(params["ontology_submission_id"])
      error 404, "`submissionId` not found" if ont_submission.nil?
      ont_submission.bring(*OntologySubmission.goo_attrs_to_load(includes_param))
      reply ont_submission
    end

    ##
    # Update an existing submission of an ontology
    REQUIRES_REPROCESS = ["prefLabelProperty", "definitionProperty", "synonymProperty", "authorProperty", "classType", "hierarchyProperty", "obsoleteProperty", "obsoleteParent"]
    patch '/:ontology_submission_id' do
      ont = Ontology.find(params["acronym"]).first
      error 422, "You must provide an existing `acronym` to patch" if ont.nil?

      submission = ont.submission(params[:ontology_submission_id])
      error 422, "You must provide an existing `submissionId` to patch" if submission.nil?

      submission.bring(*OntologySubmission.attributes)
      populate_from_params(submission, params)
      add_file_to_submission(ont, submission)

      if submission.valid?
        submission.save
        if (params.keys & REQUIRES_REPROCESS).length > 0 || request_has_file?
          cron = NcboCron::Models::OntologySubmissionParser.new
          cron.queue_submission(submission, {all: true})
        end
      else
        error 422, submission.errors
      end

      halt 204
    end

    ##
    # Delete a specific ontology submission
    delete '/:ontology_submission_id' do
      ont = Ontology.find(params["acronym"]).first
      error 422, "You must provide an existing `acronym` to delete" if ont.nil?
      submission = ont.submission(params[:ontology_submission_id])
      error 422, "You must provide an existing `submissionId` to delete" if submission.nil?
      submission.delete
      halt 204
    end

    ##
    # Download a submission
    get '/:ontology_submission_id/download' do
      acronym = params["acronym"]
      submission_attributes = [:submissionId, :submissionStatus, :uploadFilePath, :pullLocation]
      ont = Ontology.find(acronym).include(:submissions => submission_attributes).first
      error 422, "You must provide an existing `acronym` to download" if ont.nil?
      ont.bring(:viewingRestriction)
      check_access(ont)
      ont_restrict_downloads = LinkedData::OntologiesAPI.settings.restrict_download
      error 403, "License restrictions on download for #{acronym}" if ont_restrict_downloads.include? acronym
      submission = ont.submission(params['ontology_submission_id'].to_i)
      error 404, "There is no such submission for download" if submission.nil?
      file_path = submission.uploadFilePath
      if File.readable? file_path
        send_file file_path, :filename => File.basename(file_path)
      else
        if submission.pullLocation
          # Suggest using the submission.pullLocation if uploadFilePath fails.
          error 500, "Cannot read submission upload file: #{file_path}, try #{submission.pullLocation}"
        else
          error 500, "Cannot read submission upload file: #{file_path}"
        end
      end
    end

    ##
    # Download a submission diff file
    get '/:ontology_submission_id/download_diff' do
      acronym = params["acronym"]
      submission_attributes = [:submissionId, :submissionStatus, :diffFilePath]
      ont = Ontology.find(acronym).include(:submissions => submission_attributes).first
      error 422, "You must provide an existing `acronym` to download" if ont.nil?
      ont.bring(:viewingRestriction)
      check_access(ont)
      ont_restrict_downloads = LinkedData::OntologiesAPI.settings.restrict_download
      error 403, "License restrictions on download for #{acronym}" if ont_restrict_downloads.include? acronym
      submission = ont.submission(params['ontology_submission_id'].to_i)
      error 404, "There is no such submission for download" if submission.nil?
      file_path = submission.diffFilePath
      if File.readable? file_path
        send_file file_path, :filename => File.basename(file_path)
      else
        error 500, "Cannot read submission diff file: #{file_path}"
      end
    end

  end


end
