DELIMITER $$

DROP PROCEDURE IF EXISTS create_row$$

CREATE PROCEDURE create_row(
    IN p_source_transaction_id BIGINT,
    IN x_type VARCHAR(64),
    IN x_where_from VARCHAR(128),
    IN x_where_to VARCHAR(128),
    IN x_Quantity_of_parts_total DECIMAL(18,6),
    IN x_Quantity_change DECIMAL(18,6),
    IN x_Status_transaction VARCHAR(64),
    IN x_Status_warehouse VARCHAR(64),
    IN x_Order_purch VARCHAR(128),
    IN x_Order_wh VARCHAR(128),
    IN x_Order_prod VARCHAR(128),
    IN x_Order_OTK VARCHAR(128),
    IN x_Order_sv VARCHAR(128)
)
proc: BEGIN
    DECLARE v_proc_name VARCHAR(64) DEFAULT 'create_row';

    DECLARE v_source_id BIGINT DEFAULT NULL;
    DECLARE v_source_replace_to VARCHAR(255) DEFAULT NULL;
    DECLARE v_source_project VARCHAR(255) DEFAULT NULL;
    DECLARE v_source_target_assembly VARCHAR(255) DEFAULT NULL;
    DECLARE v_source_qty_in_target_assembly DECIMAL(18,6) DEFAULT NULL;
    DECLARE v_source_qty_target_assemblies DECIMAL(18,6) DEFAULT NULL;
    DECLARE v_source_for_supplied TEXT DEFAULT NULL;
    DECLARE v_source_components_qty_in_assembly DECIMAL(18,6) DEFAULT NULL;
    DECLARE v_source_assembly_batch_id VARCHAR(255) DEFAULT NULL;
    DECLARE v_source_assembly_batch_name TEXT DEFAULT NULL;
    DECLARE v_source_assembly_batch_status VARCHAR(64) DEFAULT NULL;
    DECLARE v_source_assembly_batch_priority INT DEFAULT NULL;
    DECLARE v_source_advanced_group VARCHAR(255) DEFAULT NULL;
    DECLARE v_source_document_no VARCHAR(255) DEFAULT NULL;
    DECLARE v_source_document_date DATETIME DEFAULT NULL;
    DECLARE v_source_zakaz_no VARCHAR(255) DEFAULT NULL;
    DECLARE v_source_date_needed DATETIME DEFAULT NULL;
    DECLARE v_source_date_expected DATETIME DEFAULT NULL;
    DECLARE v_source_initial_doc_no VARCHAR(255) DEFAULT NULL;

    DECLARE v_benchmark_id BIGINT DEFAULT NULL;
    DECLARE v_benchmark_supplied_component_number VARCHAR(255) DEFAULT NULL;
    DECLARE v_benchmark_component_revision VARCHAR(255) DEFAULT NULL;
    DECLARE v_benchmark_component_name VARCHAR(255) DEFAULT NULL;
    DECLARE v_benchmark_component_type VARCHAR(255) DEFAULT NULL;
    DECLARE v_benchmark_part_material VARCHAR(255) DEFAULT NULL;
    DECLARE v_benchmark_producer VARCHAR(255) DEFAULT NULL;
    DECLARE v_benchmark_catalogue_number VARCHAR(255) DEFAULT NULL;
    DECLARE v_benchmark_producer_article VARCHAR(255) DEFAULT NULL;
    DECLARE v_benchmark_distributer VARCHAR(255) DEFAULT NULL;
    DECLARE v_benchmark_distributer_article VARCHAR(255) DEFAULT NULL;
    DECLARE v_benchmark_mbom_type VARCHAR(255) DEFAULT NULL;
    DECLARE v_benchmark_mass_kg DECIMAL(18,6) DEFAULT NULL;
    DECLARE v_benchmark_unit_of_measure VARCHAR(128) DEFAULT NULL;
    DECLARE v_benchmark_height DECIMAL(18,6) DEFAULT NULL;
    DECLARE v_benchmark_width DECIMAL(18,6) DEFAULT NULL;
    DECLARE v_benchmark_length DECIMAL(18,6) DEFAULT NULL;
    DECLARE v_benchmark_location VARCHAR(255) DEFAULT NULL;

    DECLARE v_main_address VARCHAR(255) DEFAULT NULL;
    DECLARE v_main_source VARCHAR(255) DEFAULT NULL;

    SELECT
        t.id,
        t.Replace_to,
        t.Project,
        t.Target_assembly,
        t.Quantity_in_target_assembly,
        t.Quantity_of_target_assemblies,
        t.For_supplied_as_assembly_components_provided_by_supplier,
        t.Components_quantity_in_assembly,
        t.Assembly_batch_id,
        t.Assembly_batch_name,
        t.Assembly_batch_status,
        t.Assembly_batch_priority,
        t.Advanced_group,
        t.Document_no,
        t.Document_date,
        t.Zakaz_no,
        t.Date_needed,
        t.Date_expected,
        t.Initial_doc_no
    INTO
        v_source_id,
        v_source_replace_to,
        v_source_project,
        v_source_target_assembly,
        v_source_qty_in_target_assembly,
        v_source_qty_target_assemblies,
        v_source_for_supplied,
        v_source_components_qty_in_assembly,
        v_source_assembly_batch_id,
        v_source_assembly_batch_name,
        v_source_assembly_batch_status,
        v_source_assembly_batch_priority,
        v_source_advanced_group,
        v_source_document_no,
        v_source_document_date,
        v_source_zakaz_no,
        v_source_date_needed,
        v_source_date_expected,
        v_source_initial_doc_no
    FROM Transactions t
    WHERE t.id = p_source_transaction_id
      AND t.Replace_to IS NOT NULL
    ORDER BY t.created_at ASC, t.id ASC
    LIMIT 1;

    IF v_source_id IS NULL THEN
        LEAVE proc;
    END IF;

    SELECT
        t.id,
        t.Supplied_component_number,
        t.Component_revision,
        t.Component_name,
        t.Component_type,
        t.Part_material,
        t.Producer,
        t.Catalogue_number,
        t.Producer_article,
        t.Distributer,
        t.Distributer_article,
        t.MBOM_type,
        t.Mass_kg,
        t.Unit_of_measure,
        t.Height,
        t.Width,
        t.Length,
        t.Location
    INTO
        v_benchmark_id,
        v_benchmark_supplied_component_number,
        v_benchmark_component_revision,
        v_benchmark_component_name,
        v_benchmark_component_type,
        v_benchmark_part_material,
        v_benchmark_producer,
        v_benchmark_catalogue_number,
        v_benchmark_producer_article,
        v_benchmark_distributer,
        v_benchmark_distributer_article,
        v_benchmark_mbom_type,
        v_benchmark_mass_kg,
        v_benchmark_unit_of_measure,
        v_benchmark_height,
        v_benchmark_width,
        v_benchmark_length,
        v_benchmark_location
    FROM Transactions t
    WHERE t.ERP_ID = v_source_replace_to
    ORDER BY t.created_at ASC, t.id ASC
    LIMIT 1;

    IF v_benchmark_id IS NULL THEN
        UPDATE Transactions
        SET
            Order_sv = NULL,
            updated_at = NOW(),
            updated_by = CASE
                WHEN updated_by IS NULL OR TRIM(updated_by) = '' THEN v_proc_name
                ELSE CONCAT(TRIM(TRAILING ';' FROM TRIM(updated_by)), '; ', v_proc_name)
            END
        WHERE id = v_source_id;

        LEAVE proc;
    END IF;

    SELECT
        m.Address,
        m.Source
    INTO
        v_main_address,
        v_main_source
    FROM Main m
    WHERE m.ERP_ID = v_source_replace_to
    LIMIT 1;

    INSERT INTO Transactions (
        ERP_ID,
        created_at,
        updated_at,
        created_by,
        updated_by,
        linked_transaction,
        type,
        where_from,
        where_to,
        Quantity_of_parts_total,
        Quantity_change,
        Status_transaction,
        Status_warehouse,
        Project,
        Target_assembly,
        Supplied_component_number,
        Component_revision,
        Component_name,
        Quantity_in_target_assembly,
        Quantity_of_target_assemblies,
        Component_type,
        For_supplied_as_assembly_components_provided_by_supplier,
        Components_quantity_in_assembly,
        Assembly_batch_id,
        Assembly_batch_name,
        Assembly_batch_status,
        Assembly_batch_priority,
        Part_material,
        Producer,
        Catalogue_number,
        Producer_article,
        Distributer,
        Distributer_article,
        MBOM_type,
        Mass_kg,
        Unit_of_measure,
        Height,
        Width,
        Length,
        Advanced_group,
        Address,
        Recommend_purchprod,
        Order_purch,
        Order_wh,
        Order_prod,
        Order_OTK,
        Order_sv,
        Recommend_wh,
        Quantity_ordered,
        Replace_to,
        Rework_to,
        Rework_from,
        Document_no,
        Document_date,
        Zakaz_no,
        Date_needed,
        Date_expected,
        Cost_total_rub,
        Supplier,
        Location,
        Source,
        Initial_doc_no
    ) VALUES (
        v_source_replace_to,
        NOW(),
        NOW(),
        v_proc_name,
        v_proc_name,
        v_source_id,
        x_type,
        x_where_from,
        x_where_to,
        COALESCE(x_Quantity_of_parts_total, 0),
        COALESCE(x_Quantity_change, 0),
        x_Status_transaction,
        x_Status_warehouse,
        v_source_project,
        v_source_target_assembly,
        v_benchmark_supplied_component_number,
        v_benchmark_component_revision,
        v_benchmark_component_name,
        v_source_qty_in_target_assembly,
        v_source_qty_target_assemblies,
        v_benchmark_component_type,
        v_source_for_supplied,
        v_source_components_qty_in_assembly,
        v_source_assembly_batch_id,
        v_source_assembly_batch_name,
        v_source_assembly_batch_status,
        v_source_assembly_batch_priority,
        v_benchmark_part_material,
        v_benchmark_producer,
        v_benchmark_catalogue_number,
        v_benchmark_producer_article,
        v_benchmark_distributer,
        v_benchmark_distributer_article,
        v_benchmark_mbom_type,
        v_benchmark_mass_kg,
        v_benchmark_unit_of_measure,
        v_benchmark_height,
        v_benchmark_width,
        v_benchmark_length,
        v_source_advanced_group,
        v_main_address,
        NULL,
        x_Order_purch,
        x_Order_wh,
        x_Order_prod,
        x_Order_OTK,
        x_Order_sv,
        NULL,
        0,
        NULL,
        NULL,
        NULL,
        v_source_document_no,
        v_source_document_date,
        v_source_zakaz_no,
        v_source_date_needed,
        v_source_date_expected,
        NULL,
        NULL,
        v_benchmark_location,
        v_main_source,
        v_source_initial_doc_no
    );
END$$

DELIMITER ;
